#!/usr/bin/env bash
set -uo pipefail

# Exact generation-three <-> generation-four System Manager transaction for
# the first Tailscale ownership migration. The vendor apt package/unit and
# mutable /var/lib/tailscale state remain installed throughout. This program
# owns only generation-four registration/activation, the Nix-managed unit
# links, one deliberate daemon restart, and exact rollback to generation three.

profile_dir=/nix/var/nix/profiles/system-manager-profiles
profile_path=$profile_dir/system-manager
gcroot_path=/nix/var/nix/gcroots/system-manager-current
state_path=/var/lib/system-manager/state/system-manager-state.json
boot_link=/etc/systemd/system/default.target.wants/system-manager.target
nix_env=/nix/var/nix/profiles/default/bin/nix-env

generation_one_root=/nix/var/nix/gcroots/dgx-setup-root-canary-pilot
generation_two_root=/nix/var/nix/gcroots/dgx-setup-root-canary-generation-two-pilot
generation_three_root=/nix/var/nix/gcroots/dgx-setup-root-canary-boot-persistence-pilot
generation_four_root=/nix/var/nix/gcroots/dgx-setup-tailscale-migration-pilot

vendor_unit=/usr/lib/systemd/system/tailscaled.service
vendor_wants=/etc/systemd/system/multi-user.target.wants/tailscaled.service
managed_unit=/etc/systemd/system/tailscaled.service
managed_wants=/etc/systemd/system/system-manager.target.wants/tailscaled.service
tailscale_state=/var/lib/tailscale/tailscaled.state

common_paths=(
  /etc/dgx-setup/canary
  /etc/systemd/system/default.target.wants/system-manager.target
  /etc/systemd/system/dgx-setup-canary.service
  /etc/systemd/system/sysinit-reactivation.target
  /etc/systemd/system/system-manager.target
  /etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service
)

common_units=(
  dgx-setup-canary.service
  sysinit-reactivation.target
  system-manager.target
)

forbidden_paths=(
  /etc/profile.d/system-manager-path.sh
  /etc/environment.d/10-system-manager.conf
  /etc/systemd/system/system-manager-path.service
  /etc/systemd/system/userborn.service
  /run/current-system
  /run/wrappers
)

PATH=/nix/var/nix/profiles/default/bin:/usr/sbin:/usr/bin:/sbin:/bin
NIX_USER_CONF_FILES=/dev/null
export PATH NIX_USER_CONF_FILES

usage() {
  printf 'Usage: %s apply|rollback|verify-before|verify-after /nix/store/<generation-one> /nix/store/<generation-two> /nix/store/<generation-three> /nix/store/<generation-four>\n' \
    "$(basename "$0")" >&2
}

info() {
  printf 'INFO|%s|%s\n' "$1" "$2"
}

pass() {
  printf 'PASS|%s|%s\n' "$1" "$2"
}

fail() {
  printf 'FAIL|%s\n' "$1" >&2
  return 1
}

path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

raw_link() {
  readlink -- "$1" 2>/dev/null || true
}

resolved_link() {
  readlink -f -- "$1" 2>/dev/null || true
}

candidate_service_path() {
  jq -er --arg unit "$2" '.[$unit].storePath' \
    "$1/services/services.json" 2>/dev/null
}

candidate_canary_path() {
  local source

  source="$(
    jq -er '.entries["dgx-setup/canary"].source' \
      "$1/etcFiles/etcFiles.json" 2>/dev/null
  )" || return 1
  readlink -f -- "$source/dgx-setup/canary" 2>/dev/null
}

assert_candidate_shape() {
  local generation_one="$1"
  local generation_two="$2"
  local generation_three="$3"
  local generation_four="$4"
  local candidate unit generation_three_service generation_four_service
  local -a candidates=(
    "$generation_one" "$generation_two" "$generation_three" "$generation_four"
  )
  local -a roots=(
    "$generation_one_root" "$generation_two_root"
    "$generation_three_root" "$generation_four_root"
  )

  [[ "$(printf '%s\n' "${candidates[@]}" | sort -u | wc -l)" -eq 4 ]] ||
    fail "the four generation candidates are not distinct" || return 1

  for candidate in "${candidates[@]}"; do
    [[ "$candidate" =~ ^/nix/store/[a-z0-9]{32}-system-manager$ ]] ||
      fail "candidate is not an exact System Manager output: $candidate" ||
      return 1
    [[ -d "$candidate" && -x "$candidate/bin/activate" &&
      -x "$candidate/bin/register-profile" ]] ||
      fail "candidate programs are unavailable: $candidate" || return 1
  done
  [[ -x "$nix_env" ]] || fail "root-profile nix-env is unavailable" || return 1

  for candidate in "$generation_three" "$generation_four"; do
    [[ -r "$candidate/services/services.json" &&
      -r "$candidate/etcFiles/etcFiles.json" ]] ||
      fail "candidate metadata is unavailable: $candidate" || return 1
  done

  jq -e '
    (keys | sort) == [
      "dgx-setup-canary.service",
      "sysinit-reactivation.target",
      "system-manager.target"
    ]
  ' "$generation_three/services/services.json" >/dev/null ||
    fail "generation three does not have the exact three-service boundary" ||
    return 1
  jq -e '
    (keys | sort) == [
      "dgx-setup-canary.service",
      "sysinit-reactivation.target",
      "system-manager.target",
      "tailscaled.service"
    ]
  ' "$generation_four/services/services.json" >/dev/null ||
    fail "generation four does not have the exact four-service boundary" ||
    return 1

  for unit in "${common_units[@]}"; do
    generation_three_service="$(candidate_service_path "$generation_three" "$unit")" ||
      return 1
    generation_four_service="$(candidate_service_path "$generation_four" "$unit")" ||
      return 1
    [[ "$generation_three_service" == "$generation_four_service" ]] ||
      fail "generation four changed common unit $unit" || return 1
  done

  grep -Fx 'boot-persistence-generation=3' \
    "$(candidate_canary_path "$generation_three")" >/dev/null ||
    fail "generation three lacks its boot marker" || return 1
  ! grep -q '^tailscale-migration-generation=' \
    "$(candidate_canary_path "$generation_three")" ||
    fail "generation three unexpectedly contains a Tailscale marker" || return 1
  grep -Fx 'tailscale-migration-generation=4' \
    "$(candidate_canary_path "$generation_four")" >/dev/null ||
    fail "generation four lacks its exact Tailscale marker" || return 1

  for index in 0 1 2 3; do
    [[ -L "${roots[$index]}" &&
      "$(raw_link "${roots[$index]}")" == "${candidates[$index]}" ]] ||
      fail "required exact pilot root is missing: ${roots[$index]}" || return 1
  done

  [[ -f "$vendor_unit" || -L "$vendor_unit" ]] ||
    fail "vendor Tailscale unit is unavailable" || return 1
  [[ -L "$vendor_wants" && "$(resolved_link "$vendor_wants")" == "$vendor_unit" ]] ||
    fail "vendor Tailscale boot link is missing or changed" || return 1
  [[ -f "$tailscale_state" ]] || fail "mutable Tailscale state is absent" || return 1
}

assert_known_profile_surface() {
  local generation_one="$1"
  local generation_two="$2"
  local generation_three="$3"
  local generation_four="$4"
  local entry name raw expected

  [[ -d "$profile_dir" && ! -L "$profile_dir" ]] ||
    fail "System Manager profile directory is not exact" || return 1
  [[ "$(stat -c %u -- "$profile_dir" 2>/dev/null || true)" == 0 ]] ||
    fail "System Manager profile directory is not root-owned" || return 1

  while IFS= read -r entry; do
    name="${entry##*/}"
    case "$name" in
      system-manager)
        [[ -L "$entry" ]] || fail "selected profile is not a symlink" || return 1
        case "$(raw_link "$entry")" in
          system-manager-3-link)
            expected="$generation_three"
            ;;
          system-manager-4-link)
            expected="$generation_four"
            ;;
          *)
            fail "selected profile has an unknown generation"
            return 1
            ;;
        esac
        [[ "$(resolved_link "$entry")" == "$expected" ]] ||
          fail "selected profile does not resolve exactly" || return 1
        ;;
      system-manager-1-link)
        expected="$generation_one"
        ;;
      system-manager-2-link)
        expected="$generation_two"
        ;;
      system-manager-3-link)
        expected="$generation_three"
        ;;
      system-manager-4-link)
        expected="$generation_four"
        ;;
      *)
        fail "unknown System Manager profile entry: $name"
        return 1
        ;;
    esac

    if [[ "$name" != system-manager ]]; then
      raw="$(raw_link "$entry")"
      [[ -L "$entry" && "$raw" == "$expected" ]] ||
        fail "profile generation link is not exact: $entry" || return 1
    fi
  done < <(find "$profile_dir" -mindepth 1 -maxdepth 1 -printf '%p\n' | sort)

  for index in 1 2 3; do
    [[ -L "$profile_dir/system-manager-$index-link" ]] ||
      fail "required generation-$index profile link is absent" || return 1
  done
}

assert_profile_selection() {
  local generation="$1"
  local candidate="$2"
  local expected_count=$((generation + 1))
  local count

  count="$(find "$profile_dir" -mindepth 1 -maxdepth 1 -printf x | wc -c)"
  [[ "$count" -eq "$expected_count" ]] ||
    fail "profile does not have the exact generation-$generation surface" ||
    return 1
  [[ "$(raw_link "$profile_path")" == "system-manager-$generation-link" &&
    "$(resolved_link "$profile_path")" == "$candidate" ]] ||
    fail "selected profile is not exact generation $generation" || return 1
  [[ "$(raw_link "$gcroot_path")" == "$candidate" ]] ||
    fail "System Manager GC root is not exact generation $generation" || return 1
}

assert_manager_state() {
  local generation="$1"

  if [[ "$generation" -eq 3 ]]; then
    jq -e '
      .version == 1 and
      (.fileTree.backedUpFiles == []) and
      ((.fileTree.files | sort) == [
        "/etc/dgx-setup/canary",
        "/etc/systemd/system/default.target.wants/system-manager.target",
        "/etc/systemd/system/dgx-setup-canary.service",
        "/etc/systemd/system/sysinit-reactivation.target",
        "/etc/systemd/system/system-manager.target",
        "/etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service"
      ]) and
      ((.services | keys | sort) == [
        "dgx-setup-canary.service",
        "sysinit-reactivation.target",
        "system-manager.target"
      ])
    ' "$state_path" >/dev/null ||
      fail "System Manager state is not exact generation three" || return 1
  else
    jq -e '
      .version == 1 and
      (.fileTree.backedUpFiles == []) and
      ((.fileTree.files | sort) == [
        "/etc/dgx-setup/canary",
        "/etc/systemd/system/default.target.wants/system-manager.target",
        "/etc/systemd/system/dgx-setup-canary.service",
        "/etc/systemd/system/sysinit-reactivation.target",
        "/etc/systemd/system/system-manager.target",
        "/etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service",
        "/etc/systemd/system/system-manager.target.wants/tailscaled.service",
        "/etc/systemd/system/tailscaled.service"
      ]) and
      ((.services | keys | sort) == [
        "dgx-setup-canary.service",
        "sysinit-reactivation.target",
        "system-manager.target",
        "tailscaled.service"
      ])
    ' "$state_path" >/dev/null ||
      fail "System Manager state is not exact generation four" || return 1
  fi
}

assert_live_links() {
  local candidate="$1"
  local generation="$2"
  local path expected unit

  expected="$(candidate_canary_path "$candidate")" || return 1
  [[ -L /etc/dgx-setup/canary &&
    "$(resolved_link /etc/dgx-setup/canary)" == "$expected" ]] ||
    fail "live canary does not match generation $generation" || return 1

  for unit in "${common_units[@]}"; do
    expected="$(candidate_service_path "$candidate" "$unit")" || return 1
    path="/etc/systemd/system/$unit"
    [[ -L "$path" && "$(resolved_link "$path")" == "$(resolved_link "$expected")" ]] ||
      fail "live unit does not match generation $generation: $unit" || return 1
  done

  expected="$(candidate_service_path "$candidate" dgx-setup-canary.service)" ||
    return 1
  [[ -L /etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service &&
    "$(resolved_link /etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service)" == "$(resolved_link "$expected")" ]] ||
    fail "live canary dependency is not exact" || return 1

  expected="$(candidate_service_path "$candidate" system-manager.target)" || return 1
  [[ -L "$boot_link" && "$(resolved_link "$boot_link")" == "$(resolved_link "$expected")" ]] ||
    fail "boot link is not exact generation $generation" || return 1

  for path in "${forbidden_paths[@]}"; do
    ! path_exists "$path" || fail "forbidden root path exists: $path" || return 1
  done

  grep -Fx 'host=sparkle-01' /etc/dgx-setup/canary >/dev/null ||
    fail "live canary host marker is wrong" || return 1
  grep -Fx 'boot-persistence-generation=3' /etc/dgx-setup/canary >/dev/null ||
    fail "live boot marker is absent" || return 1

  for unit in dgx-setup-canary.service system-manager.target; do
    [[ "$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)" == active ]] ||
      fail "managed unit is not active: $unit" || return 1
    [[ "$(systemctl show "$unit" -p NeedDaemonReload --value 2>/dev/null || true)" == no ]] ||
      fail "managed unit needs daemon reload: $unit" || return 1
  done
}

assert_generation_three() {
  local generation_one="$1"
  local generation_two="$2"
  local generation_three="$3"
  local generation_four="$4"

  assert_candidate_shape "$generation_one" "$generation_two" "$generation_three" "$generation_four" || return 1
  assert_known_profile_surface "$generation_one" "$generation_two" "$generation_three" "$generation_four" || return 1
  assert_profile_selection 3 "$generation_three" || return 1
  assert_manager_state 3 || return 1
  assert_live_links "$generation_three" 3 || return 1
  ! grep -q '^tailscale-migration-generation=' /etc/dgx-setup/canary ||
    fail "generation-three live marker is wrong" || return 1
  ! path_exists "$managed_unit" || fail "Nix Tailscale unit exists before migration" || return 1
  ! path_exists "$managed_wants" || fail "Nix Tailscale wants link exists before migration" || return 1
  [[ "$(systemctl show tailscaled.service -p ActiveState --value 2>/dev/null || true)" == active ]] ||
    fail "vendor Tailscale service is not active" || return 1
  [[ "$(systemctl show tailscaled.service -p FragmentPath --value 2>/dev/null || true)" == "$vendor_unit" ]] ||
    fail "Tailscale is not loaded from the vendor unit" || return 1

  pass generation_three "exact boot-persistent generation three and vendor Tailscale are active"
}

assert_generation_four() {
  local generation_one="$1"
  local generation_two="$2"
  local generation_three="$3"
  local generation_four="$4"
  local expected

  assert_candidate_shape "$generation_one" "$generation_two" "$generation_three" "$generation_four" || return 1
  assert_known_profile_surface "$generation_one" "$generation_two" "$generation_three" "$generation_four" || return 1
  assert_profile_selection 4 "$generation_four" || return 1
  assert_manager_state 4 || return 1
  assert_live_links "$generation_four" 4 || return 1
  grep -Fx 'tailscale-migration-generation=4' /etc/dgx-setup/canary >/dev/null ||
    fail "generation-four live marker is wrong" || return 1

  expected="$(candidate_service_path "$generation_four" tailscaled.service)" || return 1
  [[ -L "$managed_unit" &&
    "$(resolved_link "$managed_unit")" == "$(resolved_link "$expected")" ]] ||
    fail "Nix Tailscale unit does not match generation four" || return 1
  [[ -L "$managed_wants" &&
    "$(resolved_link "$managed_wants")" == "$(resolved_link "$expected")" ]] ||
    fail "Nix Tailscale dependency does not match generation four" || return 1
  [[ "$(systemctl show tailscaled.service -p ActiveState --value 2>/dev/null || true)" == active ]] ||
    fail "Nix-managed Tailscale service is not active" || return 1
  [[ "$(systemctl show tailscaled.service -p FragmentPath --value 2>/dev/null || true)" == "$managed_unit" ]] ||
    fail "running Tailscale is not loaded from the Nix-managed unit" || return 1
  [[ "$(systemctl show tailscaled.service -p NeedDaemonReload --value 2>/dev/null || true)" == no ]] ||
    fail "Nix-managed Tailscale unit needs daemon reload" || return 1

  pass generation_four "generation four is selected, live, boot-linked, and owns running Tailscale"
}

sync_gcroot() {
  local target="$1"
  local generation_three="$2"
  local generation_four="$3"
  local temporary="$gcroot_path.dgx-tailscale-$$"
  local observed

  if path_exists "$gcroot_path"; then
    [[ -L "$gcroot_path" ]] || fail "refusing foreign GC-root collision" || return 1
    observed="$(raw_link "$gcroot_path")"
    case "$observed" in
      "$generation_three" | "$generation_four") ;;
      *)
        fail "refusing unknown System Manager GC-root target"
        return 1
        ;;
    esac
  fi
  ! path_exists "$temporary" || fail "temporary GC-root collision" || return 1
  ln -s -- "$target" "$temporary" || return 1
  if ! mv -Tf -- "$temporary" "$gcroot_path"; then
    unlink -- "$temporary" 2>/dev/null || true
    fail "could not atomically synchronize the System Manager GC root"
    return 1
  fi
  [[ "$(raw_link "$gcroot_path")" == "$target" ]] ||
    fail "GC-root synchronization did not verify" || return 1
}

restore_profile_three() {
  local generation_one="$1"
  local generation_two="$2"
  local generation_three="$3"
  local generation_four="$4"
  local generation_four_path=$profile_dir/system-manager-4-link

  assert_known_profile_surface "$generation_one" "$generation_two" "$generation_three" "$generation_four" || return 1
  if [[ "$(resolved_link "$profile_path")" != "$generation_three" ]]; then
    "$nix_env" --profile "$profile_path" --switch-generation 3 ||
      fail "could not select System Manager generation three" || return 1
  fi
  [[ "$(raw_link "$profile_path")" == system-manager-3-link &&
    "$(resolved_link "$profile_path")" == "$generation_three" ]] ||
    fail "profile did not return to exact generation three" || return 1

  if path_exists "$generation_four_path"; then
    [[ -L "$generation_four_path" && "$(raw_link "$generation_four_path")" == "$generation_four" ]] ||
      fail "refusing to remove unknown generation-four profile path" || return 1
    unlink -- "$generation_four_path" ||
      fail "could not remove exact generation-four profile link" || return 1
  fi
}

rollback_migration() {
  local generation_one="$1"
  local generation_two="$2"
  local generation_three="$3"
  local generation_four="$4"
  local activation_status=0

  assert_candidate_shape "$generation_one" "$generation_two" "$generation_three" "$generation_four" || return 1
  assert_known_profile_surface "$generation_one" "$generation_two" "$generation_three" "$generation_four" || return 1

  if "$generation_three/bin/activate"; then
    activation_status=0
  else
    activation_status=$?
    info rollback_activation "generation-three activation exited $activation_status"
  fi

  systemctl reset-failed tailscaled.service 2>/dev/null || true
  systemctl start tailscaled.service ||
    fail "vendor Tailscale service could not be restarted" || return 1
  restore_profile_three "$generation_one" "$generation_two" "$generation_three" "$generation_four" || return 1
  sync_gcroot "$generation_three" "$generation_three" "$generation_four" || return 1
  assert_generation_three "$generation_one" "$generation_two" "$generation_three" "$generation_four" || return 1
  ((activation_status == 0)) || fail "rollback activation reported failure despite recovered state" || return 1

  pass rollback "exact generation three and vendor Tailscale restored; generation-four pilot root retained"
}

validate_test_injection() {
  local stage="${DGX_TAILSCALE_MIGRATION_TEST_FAIL_STAGE:-}"

  [[ -n "$stage" ]] || return 0
  case "$stage" in
    after-registration | after-activation | after-restart) ;;
    *) fail "unknown disposable failure-injection stage: $stage"; return 1 ;;
  esac
  [[ -r /run/systemd/container && "$(< /run/systemd/container)" == systemd-nspawn ]] ||
    fail "failure injection is allowed only in a systemd-nspawn container" ||
    return 1
}

apply_migration() {
  local generation_one="$1"
  local generation_two="$2"
  local generation_three="$3"
  local generation_four="$4"

  validate_test_injection || return 1
  assert_generation_three "$generation_one" "$generation_two" "$generation_three" "$generation_four" || return 1

  if ! "$generation_four/bin/register-profile"; then
    rollback_migration "$generation_one" "$generation_two" "$generation_three" "$generation_four" || true
    fail "generation-four registration failed; rollback was attempted"
    return 1
  fi
  if [[ "${DGX_TAILSCALE_MIGRATION_TEST_FAIL_STAGE:-}" == after-registration ]]; then
    rollback_migration "$generation_one" "$generation_two" "$generation_three" "$generation_four" || return 1
    fail "disposable post-registration failure injected after successful rollback"
    return 1
  fi

  if ! "$generation_four/bin/activate"; then
    rollback_migration "$generation_one" "$generation_two" "$generation_three" "$generation_four" || true
    fail "generation-four activation failed; rollback was attempted"
    return 1
  fi
  if [[ "${DGX_TAILSCALE_MIGRATION_TEST_FAIL_STAGE:-}" == after-activation ]]; then
    rollback_migration "$generation_one" "$generation_two" "$generation_three" "$generation_four" || return 1
    fail "disposable post-activation failure injected after successful rollback"
    return 1
  fi

  if ! systemctl restart tailscaled.service; then
    rollback_migration "$generation_one" "$generation_two" "$generation_three" "$generation_four" || true
    fail "Nix-managed Tailscale restart failed; rollback was attempted"
    return 1
  fi
  if [[ "${DGX_TAILSCALE_MIGRATION_TEST_FAIL_STAGE:-}" == after-restart ]]; then
    rollback_migration "$generation_one" "$generation_two" "$generation_three" "$generation_four" || return 1
    fail "disposable post-restart failure injected after successful rollback"
    return 1
  fi

  if ! assert_generation_four "$generation_one" "$generation_two" "$generation_three" "$generation_four"; then
    rollback_migration "$generation_one" "$generation_two" "$generation_three" "$generation_four" || true
    fail "generation-four postflight failed; rollback was attempted"
    return 1
  fi

  pass transaction "generation four registered and activated with one deliberate Tailscale restart"
}

if [[ "$EUID" -ne 0 ]]; then
  fail "run this transaction as root"
  exit 1
fi

if [[ "$#" -ne 5 ]]; then
  usage
  exit 2
fi

action="$1"
generation_one="$2"
generation_two="$3"
generation_three="$4"
generation_four="$5"

case "$action" in
  apply)
    apply_migration "$generation_one" "$generation_two" "$generation_three" "$generation_four"
    ;;
  rollback)
    rollback_migration "$generation_one" "$generation_two" "$generation_three" "$generation_four"
    ;;
  verify-before)
    assert_generation_three "$generation_one" "$generation_two" "$generation_three" "$generation_four"
    ;;
  verify-after)
    assert_generation_four "$generation_one" "$generation_two" "$generation_three" "$generation_four"
    ;;
  *)
    usage
    exit 2
    ;;
esac
