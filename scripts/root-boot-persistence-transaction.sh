#!/usr/bin/env bash
set -uo pipefail

# Exact generation-two <-> boot-persistent generation-three transaction for
# the retained sparkle-01 System Manager canary. All three candidates and all
# three dedicated pilot roots must already exist. This program owns only the
# System Manager profile's generation-three link/selection, the upstream extra
# GC root, explicit activation, and the one candidate-managed boot edge. It
# never changes a pilot root, /run/current-system, a factory unit, or any other
# boot dependency.

profile_dir=/nix/var/nix/profiles/system-manager-profiles
profile_path=$profile_dir/system-manager
generation_one_path=$profile_dir/system-manager-1-link
generation_two_path=$profile_dir/system-manager-2-link
generation_three_path=$profile_dir/system-manager-3-link
gcroot_path=/nix/var/nix/gcroots/system-manager-current
generation_one_root=/nix/var/nix/gcroots/dgx-setup-root-canary-pilot
generation_two_root=/nix/var/nix/gcroots/dgx-setup-root-canary-generation-two-pilot
generation_three_root=/nix/var/nix/gcroots/dgx-setup-root-canary-boot-persistence-pilot
boot_link=/etc/systemd/system/default.target.wants/system-manager.target
nix_env=/nix/var/nix/profiles/default/bin/nix-env

managed_common_paths=(
  /etc/dgx-setup/canary
  /etc/systemd/system/dgx-setup-canary.service
  /etc/systemd/system/sysinit-reactivation.target
  /etc/systemd/system/system-manager.target
  /etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service
)

forbidden_paths=(
  /etc/profile.d/system-manager-path.sh
  /etc/environment.d/10-system-manager.conf
  /etc/systemd/system/system-manager-path.service
  /etc/systemd/system/userborn.service
  /run/wrappers
  /run/current-system
)

PATH=/nix/var/nix/profiles/default/bin:/usr/sbin:/usr/bin:/sbin:/bin
NIX_USER_CONF_FILES=/dev/null
export PATH NIX_USER_CONF_FILES

usage() {
  printf 'Usage: %s apply-boot|rollback-boot|verify-before|verify-after /nix/store/<generation-one> /nix/store/<generation-two> /nix/store/<generation-three>\n' \
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

extract_candidate_json_string() {
  local file="$1"
  local anchor="$2"
  local field="$3"
  local content tail

  [[ -r "$file" ]] ||
    fail "candidate metadata is unreadable: $file" || return 1
  content="$(<"$file")"
  tail="${content#*"$anchor"}"
  [[ "$tail" != "$content" ]] ||
    fail "candidate metadata is missing anchor $anchor" || return 1
  content="$tail"
  tail="${content#*"\"$field\":\""}"
  [[ "$tail" != "$content" ]] ||
    fail "candidate metadata is missing string field $field after $anchor" ||
    return 1
  printf '%s\n' "${tail%%\"*}"
}

candidate_canary() {
  local candidate="$1"
  local source

  source="$(
    extract_candidate_json_string \
      "$candidate/etcFiles/etcFiles.json" \
      '"dgx-setup/canary":{' source
  )" || return 1
  readlink -f -- "$source/dgx-setup/canary" 2>/dev/null || true
}

candidate_units() {
  local candidate="$1"
  local static_env

  static_env="$(
    extract_candidate_json_string \
      "$candidate/etcFiles/etcFiles.json" '"entries":{' staticEnv
  )" || return 1
  readlink -f -- "$static_env/systemd/system" 2>/dev/null || true
}

assert_candidate_shape() {
  local generation_one="$1"
  local generation_two="$2"
  local generation_three="$3"
  local candidate root expected
  local generation_two_canary generation_three_canary
  local generation_two_units generation_three_units
  local unit

  [[ "$generation_one" != "$generation_two" &&
    "$generation_one" != "$generation_three" &&
    "$generation_two" != "$generation_three" ]] ||
    fail "generation candidates are not three distinct outputs" || return 1

  for candidate in "$generation_one" "$generation_two" "$generation_three"; do
    [[ "$candidate" =~ ^/nix/store/[a-z0-9]{32}-system-manager$ ]] ||
      fail "candidate is not an exact System Manager store output: $candidate" ||
      return 1
    [[ -d "$candidate" &&
      -x "$candidate/bin/register-profile" &&
      -x "$candidate/bin/activate" ]] ||
      fail "candidate programs are unavailable: $candidate" || return 1
  done
  [[ -x "$nix_env" ]] ||
    fail "active root-profile nix-env is unavailable: $nix_env" || return 1

  for root in "$generation_one_root" "$generation_two_root" "$generation_three_root"; do
    [[ -L "$root" ]] ||
      fail "required pilot root is missing or not a symlink: $root" || return 1
  done
  [[ "$(readlink -- "$generation_one_root" 2>/dev/null || true)" == "$generation_one" ]] ||
    fail "generation-one pilot root is not exact" || return 1
  [[ "$(readlink -- "$generation_two_root" 2>/dev/null || true)" == "$generation_two" ]] ||
    fail "generation-two pilot root is not exact" || return 1
  [[ "$(readlink -- "$generation_three_root" 2>/dev/null || true)" == "$generation_three" ]] ||
    fail "generation-three pilot root is not exact" || return 1

  generation_two_canary="$(candidate_canary "$generation_two")" || return 1
  generation_three_canary="$(candidate_canary "$generation_three")" || return 1
  [[ -f "$generation_two_canary" && -f "$generation_three_canary" ]] ||
    fail "candidate canary payload is unavailable" || return 1
  grep -Fx 'registration-test-generation=2' "$generation_two_canary" >/dev/null ||
    fail "generation two lacks its exact identity marker" || return 1
  if grep -Fx 'boot-persistence-generation=3' "$generation_two_canary" >/dev/null; then
    fail "generation two unexpectedly contains the boot-persistence marker"
    return 1
  fi
  grep -Fx 'registration-test-generation=2' "$generation_three_canary" >/dev/null ||
    fail "generation three lacks the inherited generation-two marker" || return 1
  grep -Fx 'boot-persistence-generation=3' "$generation_three_canary" >/dev/null ||
    fail "generation three lacks its exact boot-persistence marker" || return 1
  cmp -s \
    <(grep -Fvx 'boot-persistence-generation=3' "$generation_three_canary") \
    "$generation_two_canary" ||
    fail "candidate canary payloads differ by more than the reviewed generation-three marker" ||
    return 1

  cmp -s "$generation_two/services/services.json" \
    "$generation_three/services/services.json" ||
    fail "generation three changes the managed service inventory" || return 1

  generation_two_units="$(candidate_units "$generation_two")" || return 1
  generation_three_units="$(candidate_units "$generation_three")" || return 1
  [[ -d "$generation_two_units" && -d "$generation_three_units" ]] ||
    fail "candidate systemd trees are unavailable" || return 1
  if path_exists "$generation_two_units/default.target.wants/system-manager.target"; then
    fail "generation two unexpectedly contains the boot edge"
    return 1
  fi
  [[ -L "$generation_three_units/default.target.wants/system-manager.target" &&
    "$(readlink -- "$generation_three_units/default.target.wants/system-manager.target")" == ../system-manager.target ]] ||
    fail "generation three lacks the exact declarative boot edge" || return 1

  for unit in \
    dgx-setup-canary.service \
    sysinit-reactivation.target \
    system-manager.target \
    system-manager.target.wants/dgx-setup-canary.service; do
    expected="$(readlink -f -- "$generation_two_units/$unit" 2>/dev/null || true)"
    [[ -n "$expected" &&
      "$(readlink -f -- "$generation_three_units/$unit" 2>/dev/null || true)" == "$expected" ]] ||
      fail "candidate systemd trees differ unexpectedly at $unit" || return 1
  done
}

assert_known_profile_surface() {
  local generation_one="$1"
  local generation_two="$2"
  local generation_three="$3"
  local entry name raw resolved
  local -a entries=()

  [[ -d "$profile_dir" && ! -L "$profile_dir" ]] ||
    fail "profile directory is missing or not a real directory" || return 1
  [[ "$(stat -c %u -- "$profile_dir" 2>/dev/null || true)" == 0 ]] ||
    fail "profile directory is not root-owned" || return 1

  mapfile -t entries < <(
    find "$profile_dir" -mindepth 1 -maxdepth 1 -printf '%p\n' | sort
  )
  [[ "${#entries[@]}" -ge 3 && "${#entries[@]}" -le 4 ]] ||
    fail "profile directory does not contain three or four exact entries" ||
    return 1

  for entry in "${entries[@]}"; do
    name="${entry##*/}"
    [[ -L "$entry" ]] ||
      fail "profile entry is not a symlink: $name" || return 1
    raw="$(readlink -- "$entry" 2>/dev/null || true)"
    resolved="$(readlink -f -- "$entry" 2>/dev/null || true)"
    case "$name" in
      system-manager)
        case "$raw" in
          system-manager-2-link)
            [[ "$resolved" == "$generation_two" ]] ||
              fail "selected generation-two profile does not resolve exactly" || return 1
            ;;
          system-manager-3-link)
            [[ "$resolved" == "$generation_three" ]] ||
              fail "selected generation-three profile does not resolve exactly" || return 1
            ;;
          *)
            fail "selected profile has an unknown raw target"
            return 1
            ;;
        esac
        ;;
      system-manager-1-link)
        [[ "$raw" == "$generation_one" && "$resolved" == "$generation_one" ]] ||
          fail "generation-one link is not exact" || return 1
        ;;
      system-manager-2-link)
        [[ "$raw" == "$generation_two" && "$resolved" == "$generation_two" ]] ||
          fail "generation-two link is not exact" || return 1
        ;;
      system-manager-3-link)
        [[ "$raw" == "$generation_three" && "$resolved" == "$generation_three" ]] ||
          fail "generation-three link is not exact" || return 1
        ;;
      *)
        fail "unknown profile entry: $name"
        return 1
        ;;
    esac
  done

  [[ -L "$profile_path" && -L "$generation_one_path" && -L "$generation_two_path" ]] ||
    fail "required profile links are missing" || return 1
}

assert_known_gcroot_surface() {
  local generation_two="$1"
  local generation_three="$2"
  local observed

  [[ -L "$gcroot_path" ]] ||
    fail "upstream extra GC root is absent or not a symlink" || return 1
  observed="$(readlink -- "$gcroot_path" 2>/dev/null || true)"
  case "$observed" in
    "$generation_two" | "$generation_three")
      ;;
    *)
      fail "upstream extra GC root has an unknown target"
      return 1
      ;;
  esac
}

assert_live_common() {
  local candidate="$1"
  local boot_expected="$2"
  local path unit canary_source
  local canary_expected canary_observed
  local service_expected sysinit_expected manager_expected
  local service_observed sysinit_observed manager_observed dependency_observed

  canary_source="$(
    extract_candidate_json_string \
      "$candidate/etcFiles/etcFiles.json" \
      '"dgx-setup/canary":{' source
  )" || return 1
  service_expected="$(
    extract_candidate_json_string \
      "$candidate/services/services.json" \
      '"dgx-setup-canary.service":{' storePath
  )" || return 1
  sysinit_expected="$(
    extract_candidate_json_string \
      "$candidate/services/services.json" \
      '"sysinit-reactivation.target":{' storePath
  )" || return 1
  manager_expected="$(
    extract_candidate_json_string \
      "$candidate/services/services.json" \
      '"system-manager.target":{' storePath
  )" || return 1

  canary_expected="$(readlink -f -- "$canary_source/dgx-setup/canary" 2>/dev/null || true)"
  canary_observed="$(readlink -f -- /etc/dgx-setup/canary 2>/dev/null || true)"
  service_expected="$(readlink -f -- "$service_expected" 2>/dev/null || true)"
  service_observed="$(readlink -f -- /etc/systemd/system/dgx-setup-canary.service 2>/dev/null || true)"
  sysinit_expected="$(readlink -f -- "$sysinit_expected" 2>/dev/null || true)"
  sysinit_observed="$(readlink -f -- /etc/systemd/system/sysinit-reactivation.target 2>/dev/null || true)"
  manager_expected="$(readlink -f -- "$manager_expected" 2>/dev/null || true)"
  manager_observed="$(readlink -f -- /etc/systemd/system/system-manager.target 2>/dev/null || true)"
  dependency_observed="$(
    readlink -f -- \
      /etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service \
      2>/dev/null || true
  )"

  [[ -n "$canary_expected" && "$canary_observed" == "$canary_expected" ]] ||
    fail "live canary payload does not match the exact candidate" || return 1
  [[ -n "$service_expected" && "$service_observed" == "$service_expected" ]] ||
    fail "live canary service does not match the exact candidate" || return 1
  [[ -n "$sysinit_expected" && "$sysinit_observed" == "$sysinit_expected" ]] ||
    fail "live sysinit target does not match the exact candidate" || return 1
  [[ -n "$manager_expected" && "$manager_observed" == "$manager_expected" ]] ||
    fail "live manager target does not match the exact candidate" || return 1
  [[ "$dependency_observed" == "$service_expected" ]] ||
    fail "live canary dependency does not match the exact candidate" || return 1

  for path in "${managed_common_paths[@]}"; do
    [[ -L "$path" ]] ||
      fail "expected managed symlink is missing at $path" || return 1
  done
  for path in "${forbidden_paths[@]}"; do
    if path_exists "$path"; then
      fail "forbidden root-manager path exists at $path"
      return 1
    fi
  done

  if [[ "$boot_expected" == true ]]; then
    [[ -L "$boot_link" &&
      "$(readlink -f -- "$boot_link" 2>/dev/null || true)" == "$manager_expected" ]] ||
      fail "live boot edge does not resolve to the exact manager target" || return 1
  elif path_exists "$boot_link"; then
    fail "boot edge exists in the no-boot generation"
    return 1
  fi

  grep -Fx 'host=sparkle-01' /etc/dgx-setup/canary >/dev/null 2>&1 ||
    fail "live canary does not identify sparkle-01" || return 1
  for unit in \
    dgx-setup-canary.service \
    sysinit-reactivation.target \
    system-manager.target; do
    [[ "$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)" == active ]] ||
      fail "managed unit $unit is not active" || return 1
    [[ "$(systemctl show "$unit" -p NeedDaemonReload --value 2>/dev/null || true)" == no ]] ||
      fail "managed unit $unit has a pending daemon reload" || return 1
  done
}

live_is_generation_two() {
  local generation_two="$1"

  assert_live_common "$generation_two" false || return 1
  grep -Fx 'registration-test-generation=2' /etc/dgx-setup/canary >/dev/null 2>&1 &&
    ! grep -Fx 'boot-persistence-generation=3' /etc/dgx-setup/canary >/dev/null 2>&1
}

live_is_generation_three() {
  local generation_three="$1"

  assert_live_common "$generation_three" true || return 1
  grep -Fx 'registration-test-generation=2' /etc/dgx-setup/canary >/dev/null 2>&1 &&
    grep -Fx 'boot-persistence-generation=3' /etc/dgx-setup/canary >/dev/null 2>&1
}

assert_generation_two_state() {
  local generation_one="$1"
  local generation_two="$2"
  local generation_three="$3"
  local -a entries=()

  assert_candidate_shape "$generation_one" "$generation_two" "$generation_three" || return 1
  assert_known_profile_surface "$generation_one" "$generation_two" "$generation_three" || return 1
  assert_known_gcroot_surface "$generation_two" "$generation_three" || return 1
  mapfile -t entries < <(
    find "$profile_dir" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort
  )
  [[ "${entries[*]}" == "system-manager system-manager-1-link system-manager-2-link" ]] ||
    fail "profile is not the exact two-generation pre-state" || return 1
  [[ "$(readlink -- "$profile_path" 2>/dev/null || true)" == system-manager-2-link &&
    "$(readlink -f -- "$profile_path" 2>/dev/null || true)" == "$generation_two" ]] ||
    fail "selected profile is not exact generation two" || return 1
  [[ "$(readlink -- "$gcroot_path" 2>/dev/null || true)" == "$generation_two" ]] ||
    fail "upstream extra GC root is not exact generation two" || return 1
  live_is_generation_two "$generation_two" ||
    fail "live activation is not exact no-boot generation two" || return 1

  pass generation_two_state "generation two is selected, rooted, and live; generation three is pilot-rooted only and boot linkage is absent"
}

assert_generation_three_registration() {
  local generation_one="$1"
  local generation_two="$2"
  local generation_three="$3"
  local -a entries=()

  assert_candidate_shape "$generation_one" "$generation_two" "$generation_three" || return 1
  assert_known_profile_surface "$generation_one" "$generation_two" "$generation_three" || return 1
  assert_known_gcroot_surface "$generation_two" "$generation_three" || return 1
  mapfile -t entries < <(
    find "$profile_dir" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort
  )
  [[ "${entries[*]}" == "system-manager system-manager-1-link system-manager-2-link system-manager-3-link" ]] ||
    fail "profile is not the exact three-generation surface" || return 1
  [[ "$(readlink -- "$profile_path" 2>/dev/null || true)" == system-manager-3-link &&
    "$(readlink -f -- "$profile_path" 2>/dev/null || true)" == "$generation_three" ]] ||
    fail "selected profile is not exact generation three" || return 1
  [[ "$(readlink -- "$gcroot_path" 2>/dev/null || true)" == "$generation_three" ]] ||
    fail "upstream extra GC root is not exact generation three" || return 1
}

assert_generation_three_state() {
  local generation_one="$1"
  local generation_two="$2"
  local generation_three="$3"

  assert_generation_three_registration "$generation_one" "$generation_two" "$generation_three" || return 1
  live_is_generation_three "$generation_three" ||
    fail "live activation is not exact boot-persistent generation three" || return 1
}

sync_gcroot() {
  local target="$1"
  local generation_two="$2"
  local generation_three="$3"
  local temporary="$gcroot_path.dgx-boot-$$"
  local observed

  if path_exists "$gcroot_path"; then
    [[ -L "$gcroot_path" ]] ||
      fail "refusing to replace foreign non-symlink GC-root collision" || return 1
    observed="$(readlink -- "$gcroot_path" 2>/dev/null || true)"
    case "$observed" in
      "$generation_two" | "$generation_three")
        ;;
      *)
        fail "refusing to replace unknown GC-root target"
        return 1
        ;;
    esac
  fi
  if path_exists "$temporary"; then
    fail "temporary GC-root path already exists: $temporary"
    return 1
  fi
  ln -s -- "$target" "$temporary" || {
    fail "could not create temporary exact GC root"
    return 1
  }
  if ! mv -Tf -- "$temporary" "$gcroot_path"; then
    unlink -- "$temporary" 2>/dev/null || true
    fail "could not atomically synchronize the upstream extra GC root"
    return 1
  fi
  [[ -L "$gcroot_path" &&
    "$(readlink -- "$gcroot_path" 2>/dev/null || true)" == "$target" ]] ||
    fail "extra GC root verification failed after synchronization" || return 1
}

restore_profile_to_generation_two() {
  local generation_one="$1"
  local generation_two="$2"
  local generation_three="$3"

  assert_known_profile_surface "$generation_one" "$generation_two" "$generation_three" || return 1
  if [[ "$(readlink -f -- "$profile_path" 2>/dev/null || true)" != "$generation_two" ]]; then
    "$nix_env" --profile "$profile_path" --switch-generation 2 || {
      fail "could not select generation two"
      return 1
    }
  fi
  [[ "$(readlink -- "$profile_path" 2>/dev/null || true)" == system-manager-2-link &&
    "$(readlink -f -- "$profile_path" 2>/dev/null || true)" == "$generation_two" ]] ||
    fail "selected profile did not return to exact generation two" || return 1

  if path_exists "$generation_three_path"; then
    [[ -L "$generation_three_path" &&
      "$(readlink -- "$generation_three_path" 2>/dev/null || true)" == "$generation_three" ]] ||
      fail "refusing to remove an unknown generation-three path" || return 1
    unlink -- "$generation_three_path" || {
      fail "could not remove exact generation-three link"
      return 1
    }
    info rollback_generation "removed exact generation-three link"
  fi
}

rollback_boot() {
  local generation_one="$1"
  local generation_two="$2"
  local generation_three="$3"

  assert_candidate_shape "$generation_one" "$generation_two" "$generation_three" || return 1
  assert_known_profile_surface "$generation_one" "$generation_two" "$generation_three" || return 1
  assert_known_gcroot_surface "$generation_two" "$generation_three" || return 1

  if ! live_is_generation_two "$generation_two"; then
    info rollback_activation "restoring exact no-boot generation-two activation"
    "$generation_two/bin/activate" || {
      fail "generation-two rollback activation failed"
      return 1
    }
    live_is_generation_two "$generation_two" ||
      fail "generation-two rollback activation did not verify" || return 1
  fi

  restore_profile_to_generation_two "$generation_one" "$generation_two" "$generation_three" || return 1
  sync_gcroot "$generation_two" "$generation_two" "$generation_three" || return 1
  assert_generation_two_state "$generation_one" "$generation_two" "$generation_three" || return 1

  pass rollback "restored exact generation-two live/profile/root state; all pilot roots remain and boot linkage is absent"
}

validate_test_injection() {
  local stage="${DGX_BOOT_PERSISTENCE_TEST_FAIL_STAGE:-}"

  [[ -n "$stage" ]] || return 0
  case "$stage" in
    upstream-gcroot-collision | after-registration | after-activation)
      ;;
    *)
      fail "unknown disposable failure-injection stage: $stage"
      return 1
      ;;
  esac
  [[ -r /run/systemd/container &&
    "$(< /run/systemd/container)" == systemd-nspawn ]] || {
    fail "failure injection is permitted only inside a systemd-nspawn container"
    return 1
  }
}

apply_boot() {
  local generation_one="$1"
  local generation_two="$2"
  local generation_three="$3"
  local register_status=0 rollback_status=0

  validate_test_injection || return 1
  assert_generation_two_state "$generation_one" "$generation_two" "$generation_three" || return 1

  if [[ "${DGX_BOOT_PERSISTENCE_TEST_FAIL_STAGE:-}" == upstream-gcroot-collision ]]; then
    unlink -- "$gcroot_path" || return 1
    printf '%s\n' disposable-foreign-collision >"$gcroot_path" || return 1
    info injection "replaced exact generation-two root with disposable foreign collision after preflight"
  fi

  if "$generation_three/bin/register-profile"; then
    register_status=0
  else
    register_status=$?
  fi
  if ((register_status != 0)); then
    info registration_failure "upstream registration exited $register_status; reconciling known profile state"
    restore_profile_to_generation_two "$generation_one" "$generation_two" "$generation_three" ||
      rollback_status=$?
    if ! sync_gcroot "$generation_two" "$generation_two" "$generation_three"; then
      rollback_status=1
    fi
    if ((rollback_status != 0)); then
      fail "generation-three registration failed; profile was reconciled where safe but foreign root state remains"
    else
      fail "generation-three registration failed; exact generation-two state was restored"
    fi
    return 1
  fi

  if ! assert_generation_three_registration "$generation_one" "$generation_two" "$generation_three"; then
    rollback_boot "$generation_one" "$generation_two" "$generation_three" || true
    fail "generation-three registration completed but verification failed; rollback was attempted"
    return 1
  fi
  if [[ "${DGX_BOOT_PERSISTENCE_TEST_FAIL_STAGE:-}" == after-registration ]]; then
    info injection "forcing failure after exact generation-three registration"
    rollback_boot "$generation_one" "$generation_two" "$generation_three" || return 1
    fail "disposable post-registration failure injected after successful rollback"
    return 1
  fi

  if ! "$generation_three/bin/activate"; then
    info activation_failure "generation-three activation failed; restoring generation two"
    rollback_boot "$generation_one" "$generation_two" "$generation_three" || true
    fail "generation-three activation failed; rollback was attempted"
    return 1
  fi
  if ! live_is_generation_three "$generation_three"; then
    rollback_boot "$generation_one" "$generation_two" "$generation_three" || true
    fail "generation-three activation completed but boot-edge verification failed; rollback was attempted"
    return 1
  fi
  if [[ "${DGX_BOOT_PERSISTENCE_TEST_FAIL_STAGE:-}" == after-activation ]]; then
    info injection "forcing failure after exact generation-three activation"
    rollback_boot "$generation_one" "$generation_two" "$generation_three" || return 1
    fail "disposable post-activation failure injected after successful rollback"
    return 1
  fi

  assert_generation_three_state "$generation_one" "$generation_two" "$generation_three" || return 1
  pass transaction "generation three is selected, rooted, live, and linked at boot; generations one/two and all pilot roots remain"
}

if [[ "$EUID" -ne 0 ]]; then
  fail "run this transaction as root"
  exit 1
fi

if [[ "$#" -ne 4 ]]; then
  usage
  exit 2
fi

action="$1"
generation_one="$2"
generation_two="$3"
generation_three="$4"

case "$action" in
  apply-boot)
    apply_boot "$generation_one" "$generation_two" "$generation_three"
    ;;
  rollback-boot)
    rollback_boot "$generation_one" "$generation_two" "$generation_three"
    ;;
  verify-before)
    assert_generation_two_state "$generation_one" "$generation_two" "$generation_three"
    ;;
  verify-after)
    assert_generation_three_state "$generation_one" "$generation_two" "$generation_three" &&
      pass generation_three_state "generation three is selected, rooted, live, and linked at boot; earlier generations remain retained"
    ;;
  *)
    usage
    exit 2
    ;;
esac
