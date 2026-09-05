#!/usr/bin/env bash
set -uo pipefail

# Exact generation-four -> first headless desktop-controller transaction for
# sparkle-01. It registers generation five, activates only the reviewed
# persistence declaration, and then explicitly isolates the headless target.
# Rollback restores exact generation four plus factory graphical.target, while
# retaining every direct pilot root. Failure injection is container-only.

profile_dir=/nix/var/nix/profiles/system-manager-profiles
profile_path=$profile_dir/system-manager
gcroot_path=/nix/var/nix/gcroots/system-manager-current
state_path=/var/lib/system-manager/state/system-manager-state.json
nix_env=/nix/var/nix/profiles/default/bin/nix-env

generation_one_root=/nix/var/nix/gcroots/dgx-setup-root-canary-pilot
generation_two_root=/nix/var/nix/gcroots/dgx-setup-root-canary-generation-two-pilot
generation_three_root=/nix/var/nix/gcroots/dgx-setup-root-canary-boot-persistence-pilot
generation_four_root=/nix/var/nix/gcroots/dgx-setup-tailscale-migration-pilot
headless_root=/nix/var/nix/gcroots/dgx-setup-desktop-headless-pilot

desktop_marker=/etc/dgx-setup/desktop-mode
default_target=/etc/systemd/system/default.target
headless_target=/etc/systemd/system/dgx-headless.target
gnome_target=/etc/systemd/system/dgx-gnome.target
managed_tailscale=/etc/systemd/system/tailscaled.service

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
  printf 'Usage: %s apply-headless|rollback-factory|verify-factory|verify-headless /nix/store/<generation-one> /nix/store/<generation-two> /nix/store/<generation-three> /nix/store/<generation-four> /nix/store/<headless>\n' \
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

candidate_entry_source() {
  jq -er --arg entry "$2" '.entries[$entry].source' \
    "$1/etcFiles/etcFiles.json" 2>/dev/null
}

candidate_canary_path() {
  local source

  source="$(candidate_entry_source "$1" dgx-setup/canary)" || return 1
  resolved_link "$source/dgx-setup/canary"
}

candidate_desktop_marker_path() {
  local source

  source="$(candidate_entry_source "$1" dgx-setup/desktop-mode)" || return 1
  resolved_link "$source/dgx-setup/desktop-mode"
}

candidate_unit_tree() {
  local source

  source="$(candidate_entry_source "$1" systemd/system)" || return 1
  resolved_link "$source/systemd/system"
}

assert_candidates_and_roots() {
  local generation_one="$1"
  local generation_two="$2"
  local generation_three="$3"
  local generation_four="$4"
  local headless="$5"
  local candidate root index
  local -a candidates=(
    "$generation_one" "$generation_two" "$generation_three"
    "$generation_four" "$headless"
  )
  local -a roots=(
    "$generation_one_root" "$generation_two_root" "$generation_three_root"
    "$generation_four_root" "$headless_root"
  )

  [[ "$(printf '%s\n' "${candidates[@]}" | sort -u | wc -l)" -eq 5 ]] ||
    fail "the five System Manager candidates are not distinct" || return 1

  for candidate in "${candidates[@]}"; do
    [[ "$candidate" =~ ^/nix/store/[a-z0-9]{32}-system-manager$ ]] ||
      fail "candidate is not an exact System Manager output: $candidate" ||
      return 1
    [[ -d "$candidate" && -x "$candidate/bin/activate" &&
      -x "$candidate/bin/register-profile" ]] ||
      fail "candidate programs are unavailable: $candidate" || return 1
    [[ -r "$candidate/services/services.json" &&
      -r "$candidate/etcFiles/etcFiles.json" ]] ||
      fail "candidate metadata is unavailable: $candidate" || return 1
  done
  [[ -x "$nix_env" ]] || fail "root-profile nix-env is unavailable" || return 1

  for index in 0 1 2 3 4; do
    root="${roots[$index]}"
    candidate="${candidates[$index]}"
    [[ -L "$root" && "$(raw_link "$root")" == "$candidate" ]] ||
      fail "required exact pilot root is missing: $root" || return 1
  done

  cmp -s "$generation_four/services/services.json" \
    "$headless/services/services.json" ||
    fail "headless candidate changed generation four's active-service map" ||
    return 1

  grep -Fx 'tailscale-migration-generation=4' \
    "$(candidate_canary_path "$generation_four")" >/dev/null ||
    fail "generation four lacks its exact Tailscale marker" || return 1
  grep -Fx 'desktop-controller-generation=5' \
    "$(candidate_canary_path "$headless")" >/dev/null ||
    fail "headless candidate lacks its controller marker" || return 1
  grep -Fx 'desktop-mode=headless' \
    "$(candidate_canary_path "$headless")" >/dev/null ||
    fail "headless candidate lacks its exact mode marker" || return 1
  grep -Fx 'mode=headless' "$(candidate_desktop_marker_path "$headless")" \
    >/dev/null || fail "headless desktop marker is invalid" || return 1

  local unit_tree
  unit_tree="$(candidate_unit_tree "$headless")" || return 1
  grep -Fx 'Requires=dgx-headless.target' "$unit_tree/default.target" \
    >/dev/null || fail "headless dispatcher dependency is invalid" || return 1
  grep -Fx 'Requires=multi-user.target system-manager.target' \
    "$unit_tree/dgx-headless.target" >/dev/null ||
    fail "headless target dependencies are invalid" || return 1
  grep -Fx 'Conflicts=dgx-gnome.target graphical.target' \
    "$unit_tree/dgx-headless.target" >/dev/null ||
    fail "headless target conflicts are invalid" || return 1
}

assert_known_profile_surface() {
  local generation_one="$1"
  local generation_two="$2"
  local generation_three="$3"
  local generation_four="$4"
  local headless="$5"
  local entry name expected raw selected_raw selected_expected
  local -a entries=()

  [[ -d "$profile_dir" && ! -L "$profile_dir" &&
    "$(stat -c %u -- "$profile_dir" 2>/dev/null || true)" == 0 ]] ||
    fail "System Manager profile directory is not exact" || return 1
  mapfile -t entries < <(
    find "$profile_dir" -mindepth 1 -maxdepth 1 -printf '%p\n' | sort
  )
  [[ "${#entries[@]}" -eq 5 || "${#entries[@]}" -eq 6 ]] ||
    fail "profile directory is not the exact four/five-generation surface" ||
    return 1

  selected_raw="$(raw_link "$profile_path")"
  case "$selected_raw" in
    system-manager-4-link) selected_expected="$generation_four" ;;
    system-manager-5-link) selected_expected="$headless" ;;
    *) fail "selected profile has an unknown generation"; return 1 ;;
  esac
  [[ "$(resolved_link "$profile_path")" == "$selected_expected" ]] ||
    fail "selected profile does not resolve exactly" || return 1

  for entry in "${entries[@]}"; do
    name="${entry##*/}"
    case "$name" in
      system-manager) continue ;;
      system-manager-1-link) expected="$generation_one" ;;
      system-manager-2-link) expected="$generation_two" ;;
      system-manager-3-link) expected="$generation_three" ;;
      system-manager-4-link) expected="$generation_four" ;;
      system-manager-5-link) expected="$headless" ;;
      *) fail "unknown System Manager profile entry: $name"; return 1 ;;
    esac
    raw="$(raw_link "$entry")"
    [[ -L "$entry" && "$raw" == "$expected" ]] ||
      fail "profile generation link is not exact: $entry" || return 1
  done

  for index in 1 2 3 4; do
    [[ -L "$profile_dir/system-manager-$index-link" ]] ||
      fail "required generation-$index profile link is absent" || return 1
  done
}

assert_known_gcroot() {
  local generation_four="$1"
  local headless="$2"
  local observed

  [[ -L "$gcroot_path" ]] ||
    fail "System Manager upstream GC root is absent or foreign" || return 1
  observed="$(raw_link "$gcroot_path")"
  case "$observed" in
    "$generation_four" | "$headless") ;;
    *) fail "System Manager upstream GC root has an unknown target"; return 1 ;;
  esac
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
  [[ "$(raw_link "$profile_dir/system-manager-$generation-link")" == "$candidate" ]] ||
    fail "numbered profile is not exact generation $generation" || return 1
  [[ "$(raw_link "$gcroot_path")" == "$candidate" ]] ||
    fail "upstream GC root is not exact generation $generation" || return 1
}

assert_manager_state() {
  local mode="$1"

  if [[ "$mode" == factory ]]; then
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
  else
    jq -e '
      .version == 1 and
      (.fileTree.backedUpFiles == []) and
      ((.fileTree.files | sort) == [
        "/etc/dgx-setup/canary",
        "/etc/dgx-setup/desktop-mode",
        "/etc/systemd/system/default.target",
        "/etc/systemd/system/default.target.wants/system-manager.target",
        "/etc/systemd/system/dgx-gnome.target",
        "/etc/systemd/system/dgx-headless.target",
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
      fail "System Manager state is not exact headless generation five" ||
      return 1
  fi
}

assert_live_common() {
  local candidate="$1"
  local expected path unit

  expected="$(candidate_canary_path "$candidate")" || return 1
  [[ -L /etc/dgx-setup/canary &&
    "$(resolved_link /etc/dgx-setup/canary)" == "$expected" ]] ||
    fail "live canary does not match the exact candidate" || return 1

  for unit in \
    dgx-setup-canary.service sysinit-reactivation.target \
    system-manager.target tailscaled.service; do
    expected="$(candidate_service_path "$candidate" "$unit")" || return 1
    path="/etc/systemd/system/$unit"
    [[ -L "$path" &&
      "$(resolved_link "$path")" == "$(resolved_link "$expected")" ]] ||
      fail "live unit does not match the exact candidate: $unit" || return 1
    [[ "$(systemctl show "$unit" -p NeedDaemonReload --value 2>/dev/null || true)" == no ]] ||
      fail "managed unit needs daemon reload: $unit" || return 1
  done

  expected="$(candidate_service_path "$candidate" dgx-setup-canary.service)" ||
    return 1
  [[ "$(resolved_link /etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service)" == \
    "$(resolved_link "$expected")" ]] ||
    fail "live canary dependency is not exact" || return 1
  expected="$(candidate_service_path "$candidate" tailscaled.service)" || return 1
  [[ "$(resolved_link /etc/systemd/system/system-manager.target.wants/tailscaled.service)" == \
    "$(resolved_link "$expected")" ]] ||
    fail "live Tailscale dependency is not exact" || return 1
  expected="$(candidate_service_path "$candidate" system-manager.target)" || return 1
  [[ "$(resolved_link /etc/systemd/system/default.target.wants/system-manager.target)" == \
    "$(resolved_link "$expected")" ]] ||
    fail "live System Manager boot dependency is not exact" || return 1

  for path in "${forbidden_paths[@]}"; do
    ! path_exists "$path" || fail "forbidden root path exists: $path" || return 1
  done
  for unit in dgx-setup-canary.service system-manager.target tailscaled.service; do
    [[ "$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)" == active ]] ||
      fail "managed unit is not active: $unit" || return 1
  done
  [[ "$(systemctl show tailscaled.service -p FragmentPath --value 2>/dev/null || true)" == \
    "$managed_tailscale" ]] ||
    fail "Tailscale is not loaded from the Nix-managed unit" || return 1
  grep -Fx 'host=sparkle-01' /etc/dgx-setup/canary >/dev/null ||
    fail "live canary host marker is wrong" || return 1
  grep -Fx 'tailscale-migration-generation=4' /etc/dgx-setup/canary >/dev/null ||
    fail "live Tailscale marker is absent" || return 1
}

assert_factory_runtime() {
  local path

  for path in "$desktop_marker" "$default_target" "$headless_target" "$gnome_target"; do
    ! path_exists "$path" || fail "desktop-controller path exists in factory mode: $path" || return 1
  done
  [[ "$(systemctl get-default 2>/dev/null || true)" == graphical.target ]] ||
    fail "factory default target is not graphical.target" || return 1
  for unit in graphical.target gdm.service; do
    [[ "$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)" == active ]] ||
      fail "factory graphical unit is not active: $unit" || return 1
  done
  [[ "$(systemctl show dgx-headless.target -p LoadState --value 2>/dev/null || true)" == not-found ]] ||
    fail "headless target remains loaded in factory mode" || return 1
}

assert_headless_runtime() {
  local headless="$1"
  local expected unit_tree

  unit_tree="$(candidate_unit_tree "$headless")" || return 1
  expected="$(candidate_desktop_marker_path "$headless")" || return 1
  [[ -L "$desktop_marker" && "$(resolved_link "$desktop_marker")" == "$expected" ]] ||
    fail "live desktop marker does not match headless candidate" || return 1
  for path in "$default_target" "$headless_target" "$gnome_target"; do
    [[ -L "$path" ]] || fail "headless controller path is missing: $path" || return 1
    [[ "$(resolved_link "$path")" == "$(resolved_link "$unit_tree/${path##*/}")" ]] ||
      fail "headless controller path is not exact: $path" || return 1
  done
  [[ "$(systemctl get-default 2>/dev/null || true)" == default.target ]] ||
    fail "linked headless dispatcher is not the reported default" || return 1
  [[ "$(systemctl show dgx-headless.target -p ActiveState --value 2>/dev/null || true)" == active ]] ||
    fail "headless target is not active" || return 1
  for unit in dgx-gnome.target graphical.target gdm.service; do
    [[ "$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)" != active ]] ||
      fail "graphical unit remains active in headless mode: $unit" || return 1
  done
  grep -Fx 'mode=headless' "$desktop_marker" >/dev/null ||
    fail "live desktop marker does not say headless" || return 1
}

assert_factory_state() {
  local generation_one="$1"
  local generation_two="$2"
  local generation_three="$3"
  local generation_four="$4"
  local headless="$5"

  assert_candidates_and_roots "$@" || return 1
  assert_known_profile_surface "$@" || return 1
  assert_known_gcroot "$generation_four" "$headless" || return 1
  assert_profile_selection 4 "$generation_four" || return 1
  assert_manager_state factory || return 1
  assert_live_common "$generation_four" || return 1
  ! grep -q '^desktop-controller-generation=' /etc/dgx-setup/canary ||
    fail "factory generation unexpectedly has a desktop marker" || return 1
  assert_factory_runtime || return 1
  pass factory_state "generation four is selected/live with factory GNOME; headless is pilot-rooted only"
}

assert_headless_state() {
  local generation_one="$1"
  local generation_two="$2"
  local generation_three="$3"
  local generation_four="$4"
  local headless="$5"

  assert_candidates_and_roots "$@" || return 1
  assert_known_profile_surface "$@" || return 1
  assert_known_gcroot "$generation_four" "$headless" || return 1
  assert_profile_selection 5 "$headless" || return 1
  assert_manager_state headless || return 1
  assert_live_common "$headless" || return 1
  grep -Fx 'desktop-controller-generation=5' /etc/dgx-setup/canary >/dev/null ||
    fail "live headless generation lacks controller marker" || return 1
  grep -Fx 'desktop-mode=headless' /etc/dgx-setup/canary >/dev/null ||
    fail "live headless generation lacks mode marker" || return 1
  assert_headless_runtime "$headless" || return 1
  pass headless_state "generation five is selected/live in headless mode; factory GNOME remains installed"
}

sync_gcroot() {
  local target="$1"
  local generation_four="$2"
  local headless="$3"
  local temporary="$gcroot_path.dgx-desktop-$$"
  local observed

  if path_exists "$gcroot_path"; then
    [[ -L "$gcroot_path" ]] || fail "refusing foreign GC-root collision" || return 1
    observed="$(raw_link "$gcroot_path")"
    case "$observed" in
      "$generation_four" | "$headless") ;;
      *) fail "refusing unknown System Manager GC-root target"; return 1 ;;
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

restore_profile_four() {
  local generation_one="$1"
  local generation_two="$2"
  local generation_three="$3"
  local generation_four="$4"
  local headless="$5"
  local generation_five_path=$profile_dir/system-manager-5-link

  assert_known_profile_surface "$@" || return 1
  if [[ "$(resolved_link "$profile_path")" != "$generation_four" ]]; then
    "$nix_env" --profile "$profile_path" --switch-generation 4 ||
      fail "could not select System Manager generation four" || return 1
  fi
  [[ "$(raw_link "$profile_path")" == system-manager-4-link &&
    "$(resolved_link "$profile_path")" == "$generation_four" ]] ||
    fail "profile did not return to exact generation four" || return 1

  if path_exists "$generation_five_path"; then
    [[ -L "$generation_five_path" &&
      "$(raw_link "$generation_five_path")" == "$headless" ]] ||
      fail "refusing to remove unknown generation-five profile path" || return 1
    unlink -- "$generation_five_path" ||
      fail "could not remove exact generation-five profile link" || return 1
  fi
}

activate_exact() {
  local candidate="$1"
  local logs status=0

  logs="$("$candidate/bin/activate" 2>&1)" || status=$?
  printf '%s\n' "$logs"
  ((status == 0)) || return "$status"
  ! grep -q ' ERROR ' <<<"$logs" || {
    fail "System Manager activation logged an error"
    return 1
  }
}

rollback_factory() {
  local generation_one="$1"
  local generation_two="$2"
  local generation_three="$3"
  local generation_four="$4"
  local headless="$5"

  assert_candidates_and_roots "$@" || return 1
  assert_known_profile_surface "$@" || return 1
  assert_known_gcroot "$generation_four" "$headless" || return 1

  if ! assert_manager_state factory >/dev/null 2>&1 ||
    ! assert_factory_runtime >/dev/null 2>&1; then
    info rollback_activation "restoring exact generation four and factory graphical target"
    activate_exact "$generation_four" ||
      fail "generation-four rollback activation failed" || return 1
    systemctl start system-manager.target graphical.target ||
      fail "factory graphical target could not be restored" || return 1
  fi

  restore_profile_four "$@" || return 1
  sync_gcroot "$generation_four" "$generation_four" "$headless" || return 1
  assert_factory_state "$@" || return 1
  pass rollback "exact generation four and factory GNOME restored; all pilot roots remain"
}

validate_test_injection() {
  local stage="${DGX_DESKTOP_MODE_TEST_FAIL_STAGE:-}"

  [[ -n "$stage" ]] || return 0
  case "$stage" in
    upstream-gcroot-collision | after-registration | after-activation | after-isolate) ;;
    *) fail "unknown disposable failure-injection stage: $stage"; return 1 ;;
  esac
  [[ -r /run/systemd/container &&
    "$(< /run/systemd/container)" == systemd-nspawn ]] ||
    fail "failure injection is allowed only in a systemd-nspawn container" ||
    return 1
}

apply_headless() {
  local generation_one="$1"
  local generation_two="$2"
  local generation_three="$3"
  local generation_four="$4"
  local headless="$5"
  local register_status=0 rollback_status=0

  validate_test_injection || return 1
  assert_factory_state "$@" || return 1

  if [[ "${DGX_DESKTOP_MODE_TEST_FAIL_STAGE:-}" == upstream-gcroot-collision ]]; then
    unlink -- "$gcroot_path" || return 1
    printf '%s\n' disposable-foreign-collision >"$gcroot_path" || return 1
    info injection "installed a disposable foreign root after preflight"
  fi

  "$headless/bin/register-profile" || register_status=$?
  if ((register_status != 0)); then
    info registration_failure "headless registration exited $register_status; reconciling known profile state"
    restore_profile_four "$@" || rollback_status=$?
    if ! sync_gcroot "$generation_four" "$generation_four" "$headless"; then
      rollback_status=1
    fi
    if ((rollback_status != 0)); then
      fail "headless registration failed; profile was reconciled where safe but foreign root state remains"
    else
      fail "headless registration failed; exact generation-four state was restored"
    fi
    return 1
  fi

  assert_known_profile_surface "$@" || return 1
  assert_profile_selection 5 "$headless" || {
    rollback_factory "$@" || true
    fail "headless registration completed but exact generation five did not verify"
    return 1
  }

  if [[ "${DGX_DESKTOP_MODE_TEST_FAIL_STAGE:-}" == after-registration ]]; then
    rollback_factory "$@" || return 1
    fail "disposable post-registration failure injected after successful rollback"
    return 1
  fi

  if ! activate_exact "$headless"; then
    rollback_factory "$@" || true
    fail "headless activation failed; factory rollback was attempted"
    return 1
  fi
  if [[ "${DGX_DESKTOP_MODE_TEST_FAIL_STAGE:-}" == after-activation ]]; then
    rollback_factory "$@" || return 1
    fail "disposable post-activation failure injected after successful rollback"
    return 1
  fi

  if ! systemctl isolate dgx-headless.target; then
    rollback_factory "$@" || true
    fail "headless target isolation failed; factory rollback was attempted"
    return 1
  fi
  if [[ "${DGX_DESKTOP_MODE_TEST_FAIL_STAGE:-}" == after-isolate ]]; then
    rollback_factory "$@" || return 1
    fail "disposable post-isolation failure injected after successful rollback"
    return 1
  fi

  if ! assert_headless_state "$@"; then
    rollback_factory "$@" || true
    fail "headless postflight failed; factory rollback was attempted"
    return 1
  fi
  pass transaction "generation five registered/activated and headless target isolated; generation four remains retained"
}

if [[ "$EUID" -ne 0 ]]; then
  fail "run this transaction as root"
  exit 1
fi

if [[ "$#" -ne 6 ]]; then
  usage
  exit 2
fi

action="$1"
generation_one="$2"
generation_two="$3"
generation_three="$4"
generation_four="$5"
headless="$6"

case "$action" in
  apply-headless)
    apply_headless "$generation_one" "$generation_two" "$generation_three" \
      "$generation_four" "$headless"
    ;;
  rollback-factory)
    rollback_factory "$generation_one" "$generation_two" "$generation_three" \
      "$generation_four" "$headless"
    ;;
  verify-factory)
    assert_factory_state "$generation_one" "$generation_two" "$generation_three" \
      "$generation_four" "$headless"
    ;;
  verify-headless)
    assert_headless_state "$generation_one" "$generation_two" "$generation_three" \
      "$generation_four" "$headless"
    ;;
  *)
    usage
    exit 2
    ;;
esac
