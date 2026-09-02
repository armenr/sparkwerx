#!/usr/bin/env bash
set -uo pipefail

# Exact generation-one <-> generation-two transaction for the retained
# sparkle-01 System Manager canary. The candidates must differ only in the
# harmless canary payload already constrained by flake policy. This program
# owns the dedicated System Manager profile selection, its numbered generation
# two link, the upstream extra GC root, and explicit activation of one of the
# two exact candidates. It never adds boot linkage, changes the pilot roots,
# broadens the managed service set, or touches a factory-owned service.

profile_dir=/nix/var/nix/profiles/system-manager-profiles
profile_path=$profile_dir/system-manager
generation_one_path=$profile_dir/system-manager-1-link
generation_two_path=$profile_dir/system-manager-2-link
gcroot_path=/nix/var/nix/gcroots/system-manager-current
pilot_root=/nix/var/nix/gcroots/dgx-setup-root-canary-pilot
generation_two_root=/nix/var/nix/gcroots/dgx-setup-root-canary-generation-two-pilot
boot_link=/etc/systemd/system/default.target.wants/system-manager.target
nix_env=/nix/var/nix/profiles/default/bin/nix-env

managed_paths=(
  /etc/dgx-setup/canary
  /etc/systemd/system/dgx-setup-canary.service
  /etc/systemd/system/sysinit-reactivation.target
  /etc/systemd/system/system-manager.target
  /etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service
)

forbidden_paths=(
  /etc/profile.d/system-manager-path.sh
  /etc/environment.d/10-system-manager.conf
  $boot_link
  /etc/systemd/system/system-manager-path.service
  /etc/systemd/system/userborn.service
  /run/wrappers
  /run/current-system
)

PATH=/nix/var/nix/profiles/default/bin:/usr/sbin:/usr/bin:/sbin:/bin
NIX_USER_CONF_FILES=/dev/null
export PATH NIX_USER_CONF_FILES

usage() {
  printf 'Usage: %s apply-switch|rollback-switch|verify-before|verify-after /nix/store/<generation-one> /nix/store/<generation-two>\n' \
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

assert_exact_candidates_and_retention() {
  local generation_one="$1"
  local generation_two="$2"
  local candidate

  [[ "$generation_one" != "$generation_two" ]] ||
    fail "generation candidates are identical" || return 1

  for candidate in "$generation_one" "$generation_two"; do
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

  [[ -L "$pilot_root" &&
    "$(readlink -- "$pilot_root" 2>/dev/null || true)" == "$generation_one" ]] ||
    fail "generation-one pilot root is missing or not exact" || return 1
  [[ -L "$generation_two_root" &&
    "$(readlink -- "$generation_two_root" 2>/dev/null || true)" == "$generation_two" ]] ||
    fail "generation-two pilot root is missing or not exact" || return 1

  if path_exists "$boot_link"; then
    fail "boot linkage is forbidden during the generation-switch milestone"
    return 1
  fi
}

assert_known_profile_surface() {
  local generation_one="$1"
  local generation_two="$2"
  local entry name
  local -a entries=()

  [[ -d "$profile_dir" && ! -L "$profile_dir" ]] ||
    fail "profile directory is missing or not a real directory" || return 1
  [[ "$(stat -c %u -- "$profile_dir" 2>/dev/null || true)" == 0 ]] ||
    fail "profile directory is not root-owned" || return 1

  mapfile -t entries < <(
    find "$profile_dir" -mindepth 1 -maxdepth 1 -printf '%p\n' | sort
  )
  [[ "${#entries[@]}" -ge 2 && "${#entries[@]}" -le 3 ]] ||
    fail "profile directory does not contain two or three exact entries" ||
    return 1

  for entry in "${entries[@]}"; do
    name="${entry##*/}"
    case "$name" in
      system-manager)
        [[ -L "$entry" ]] ||
          fail "selected profile is not a symlink" || return 1
        case "$(readlink -- "$entry" 2>/dev/null || true)" in
          system-manager-1-link)
            [[ "$(readlink -f -- "$entry" 2>/dev/null || true)" == "$generation_one" ]] ||
              fail "selected generation-one profile does not resolve exactly" || return 1
            ;;
          system-manager-2-link)
            [[ "$(readlink -f -- "$entry" 2>/dev/null || true)" == "$generation_two" ]] ||
              fail "selected generation-two profile does not resolve exactly" || return 1
            ;;
          *)
            fail "selected profile has an unknown raw target"
            return 1
            ;;
        esac
        ;;
      system-manager-1-link)
        [[ -L "$entry" &&
          "$(readlink -- "$entry" 2>/dev/null || true)" == "$generation_one" ]] ||
          fail "generation-one link is missing or not exact" || return 1
        ;;
      system-manager-2-link)
        [[ -L "$entry" &&
          "$(readlink -- "$entry" 2>/dev/null || true)" == "$generation_two" ]] ||
          fail "generation-two link is not exact" || return 1
        ;;
      *)
        fail "unknown profile entry: $name"
        return 1
        ;;
    esac
  done

  [[ -L "$profile_path" && -L "$generation_one_path" ]] ||
    fail "required profile links are missing" || return 1
}

assert_known_gcroot_surface() {
  local generation_one="$1"
  local generation_two="$2"
  local observed

  [[ -L "$gcroot_path" ]] ||
    fail "upstream extra GC root is absent or not a symlink" || return 1
  observed="$(readlink -- "$gcroot_path" 2>/dev/null || true)"
  case "$observed" in
    "$generation_one" | "$generation_two")
      ;;
    *)
      fail "upstream extra GC root has an unknown target"
      return 1
      ;;
  esac
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

assert_live_common() {
  local candidate="$1"
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

  canary_expected="$(
    readlink -f -- "$canary_source/dgx-setup/canary" 2>/dev/null || true
  )"
  canary_observed="$(
    readlink -f -- /etc/dgx-setup/canary 2>/dev/null || true
  )"
  service_expected="$(readlink -f -- "$service_expected" 2>/dev/null || true)"
  service_observed="$(
    readlink -f -- /etc/systemd/system/dgx-setup-canary.service \
      2>/dev/null || true
  )"
  sysinit_expected="$(readlink -f -- "$sysinit_expected" 2>/dev/null || true)"
  sysinit_observed="$(
    readlink -f -- /etc/systemd/system/sysinit-reactivation.target \
      2>/dev/null || true
  )"
  manager_expected="$(readlink -f -- "$manager_expected" 2>/dev/null || true)"
  manager_observed="$(
    readlink -f -- /etc/systemd/system/system-manager.target \
      2>/dev/null || true
  )"
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

  for path in "${managed_paths[@]}"; do
    [[ -L "$path" ]] ||
      fail "expected managed symlink is missing at $path" || return 1
  done
  for path in "${forbidden_paths[@]}"; do
    if path_exists "$path"; then
      fail "forbidden root-manager path exists at $path"
      return 1
    fi
  done

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

live_is_generation_one() {
  local generation_one="$1"

  assert_live_common "$generation_one" || return 1
  ! grep -Fx 'registration-test-generation=2' /etc/dgx-setup/canary \
    >/dev/null 2>&1
}

live_is_generation_two() {
  local generation_two="$1"

  assert_live_common "$generation_two" || return 1
  grep -Fx 'registration-test-generation=2' /etc/dgx-setup/canary \
    >/dev/null 2>&1
}

assert_generation_one_registration() {
  local generation_one="$1"
  local generation_two="$2"
  local -a entries=()

  assert_exact_candidates_and_retention "$generation_one" "$generation_two" ||
    return 1
  assert_known_profile_surface "$generation_one" "$generation_two" || return 1

  mapfile -t entries < <(
    find "$profile_dir" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort
  )
  [[ "${#entries[@]}" -eq 2 &&
    "${entries[0]:-}" == system-manager &&
    "${entries[1]:-}" == system-manager-1-link ]] ||
    fail "profile is not the exact generation-one pre-state" || return 1
  [[ "$(readlink -- "$profile_path" 2>/dev/null || true)" == system-manager-1-link &&
    "$(readlink -f -- "$profile_path" 2>/dev/null || true)" == "$generation_one" ]] ||
    fail "selected profile is not exact generation one" || return 1
  [[ -L "$gcroot_path" &&
    "$(readlink -- "$gcroot_path" 2>/dev/null || true)" == "$generation_one" ]] ||
    fail "upstream extra GC root is not exact generation one" || return 1
  live_is_generation_one "$generation_one" ||
    fail "live activation is not exact generation one" || return 1

  pass generation_one_state "generation one is selected, rooted, and live; generation two is only pilot-rooted"
}

assert_generation_two_registration() {
  local generation_one="$1"
  local generation_two="$2"
  local -a entries=()

  assert_exact_candidates_and_retention "$generation_one" "$generation_two" ||
    return 1
  assert_known_profile_surface "$generation_one" "$generation_two" || return 1

  mapfile -t entries < <(
    find "$profile_dir" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort
  )
  [[ "${#entries[@]}" -eq 3 &&
    "${entries[0]:-}" == system-manager &&
    "${entries[1]:-}" == system-manager-1-link &&
    "${entries[2]:-}" == system-manager-2-link ]] ||
    fail "profile is not the exact two-generation surface" || return 1
  [[ "$(readlink -- "$profile_path" 2>/dev/null || true)" == system-manager-2-link &&
    "$(readlink -f -- "$profile_path" 2>/dev/null || true)" == "$generation_two" ]] ||
    fail "selected profile is not exact generation two" || return 1
  [[ -L "$gcroot_path" &&
    "$(readlink -- "$gcroot_path" 2>/dev/null || true)" == "$generation_two" ]] ||
    fail "upstream extra GC root is not exact generation two" || return 1
}

sync_gcroot() {
  local target="$1"
  local generation_one="$2"
  local generation_two="$3"
  local temporary="$gcroot_path.dgx-switch-$$"
  local observed

  if path_exists "$gcroot_path"; then
    [[ -L "$gcroot_path" ]] ||
      fail "refusing to replace foreign non-symlink GC-root collision" ||
      return 1
    observed="$(readlink -- "$gcroot_path" 2>/dev/null || true)"
    case "$observed" in
      "$generation_one" | "$generation_two")
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

restore_profile_to_generation_one() {
  local generation_one="$1"
  local generation_two="$2"

  assert_known_profile_surface "$generation_one" "$generation_two" || return 1

  if [[ "$(readlink -f -- "$profile_path" 2>/dev/null || true)" != "$generation_one" ]]; then
    "$nix_env" --profile "$profile_path" --switch-generation 1 || {
      fail "could not select generation one"
      return 1
    }
  fi
  [[ "$(readlink -- "$profile_path" 2>/dev/null || true)" == system-manager-1-link &&
    "$(readlink -f -- "$profile_path" 2>/dev/null || true)" == "$generation_one" ]] ||
    fail "selected profile did not return to exact generation one" || return 1

  if path_exists "$generation_two_path"; then
    [[ -L "$generation_two_path" &&
      "$(readlink -- "$generation_two_path" 2>/dev/null || true)" == "$generation_two" ]] ||
      fail "refusing to remove an unknown generation-two path" || return 1
    unlink -- "$generation_two_path" || {
      fail "could not remove exact generation-two link"
      return 1
    }
    info rollback_generation "removed exact generation-two link"
  fi
}

restore_registration_to_generation_one() {
  local generation_one="$1"
  local generation_two="$2"

  restore_profile_to_generation_one "$generation_one" "$generation_two" ||
    return 1
  sync_gcroot "$generation_one" "$generation_one" "$generation_two" ||
    return 1
}

rollback_switch() {
  local generation_one="$1"
  local generation_two="$2"

  assert_exact_candidates_and_retention "$generation_one" "$generation_two" ||
    return 1
  assert_known_profile_surface "$generation_one" "$generation_two" || return 1
  assert_known_gcroot_surface "$generation_one" "$generation_two" || return 1

  if ! live_is_generation_one "$generation_one"; then
    info rollback_activation "restoring exact generation-one activation"
    "$generation_one/bin/activate" || {
      fail "generation-one rollback activation failed"
      return 1
    }
    live_is_generation_one "$generation_one" ||
      fail "generation-one rollback activation did not verify" || return 1
  fi

  restore_registration_to_generation_one "$generation_one" "$generation_two" ||
    return 1
  assert_generation_one_registration "$generation_one" "$generation_two" ||
    return 1

  pass rollback "restored exact generation-one live/profile/root state; both pilot roots remain and boot linkage stays absent"
}

validate_test_injection() {
  local stage="${DGX_GENERATION_SWITCH_TEST_FAIL_STAGE:-}"

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

apply_switch() {
  local generation_one="$1"
  local generation_two="$2"
  local register_status=0 rollback_status=0

  validate_test_injection || return 1
  assert_generation_one_registration "$generation_one" "$generation_two" ||
    return 1

  if [[ "${DGX_GENERATION_SWITCH_TEST_FAIL_STAGE:-}" == upstream-gcroot-collision ]]; then
    unlink -- "$gcroot_path" || return 1
    printf '%s\n' disposable-foreign-collision >"$gcroot_path" || return 1
    info injection "replaced exact generation-one root with disposable foreign collision after preflight"
  fi

  if "$generation_two/bin/register-profile"; then
    register_status=0
  else
    register_status=$?
  fi

  if ((register_status != 0)); then
    info registration_failure "upstream registration exited $register_status; reconciling known profile state"
    restore_profile_to_generation_one "$generation_one" "$generation_two" ||
      rollback_status=$?
    if ! sync_gcroot "$generation_one" "$generation_one" "$generation_two"; then
      rollback_status=1
    fi
    if ((rollback_status != 0)); then
      fail "generation-two registration failed; profile was reconciled where safe but foreign root state remains"
    else
      fail "generation-two registration failed; exact generation-one state was restored"
    fi
    return 1
  fi

  if ! assert_generation_two_registration "$generation_one" "$generation_two"; then
    rollback_switch "$generation_one" "$generation_two" || true
    fail "generation-two registration completed but verification failed; rollback was attempted"
    return 1
  fi

  if [[ "${DGX_GENERATION_SWITCH_TEST_FAIL_STAGE:-}" == after-registration ]]; then
    info injection "forcing failure after exact generation-two registration"
    rollback_switch "$generation_one" "$generation_two" || return 1
    fail "disposable post-registration failure injected after successful rollback"
    return 1
  fi

  if ! "$generation_two/bin/activate"; then
    info activation_failure "generation-two activation failed; restoring generation one"
    rollback_switch "$generation_one" "$generation_two" || true
    fail "generation-two activation failed; rollback was attempted"
    return 1
  fi

  if ! live_is_generation_two "$generation_two"; then
    rollback_switch "$generation_one" "$generation_two" || true
    fail "generation-two activation completed but live verification failed; rollback was attempted"
    return 1
  fi

  if [[ "${DGX_GENERATION_SWITCH_TEST_FAIL_STAGE:-}" == after-activation ]]; then
    info injection "forcing failure after exact generation-two activation"
    rollback_switch "$generation_one" "$generation_two" || return 1
    fail "disposable post-activation failure injected after successful rollback"
    return 1
  fi

  assert_generation_two_registration "$generation_one" "$generation_two" ||
    return 1
  pass transaction "generation two is selected, extra-rooted, and live; generation one and both pilot roots remain; boot linkage is absent"
}

if [[ "$EUID" -ne 0 ]]; then
  fail "run this transaction as root"
  exit 1
fi

if [[ "$#" -ne 3 ]]; then
  usage
  exit 2
fi

action="$1"
generation_one="$2"
generation_two="$3"

case "$action" in
  apply-switch)
    apply_switch "$generation_one" "$generation_two"
    ;;
  rollback-switch)
    rollback_switch "$generation_one" "$generation_two"
    ;;
  verify-before)
    assert_generation_one_registration "$generation_one" "$generation_two"
    ;;
  verify-after)
    assert_generation_two_registration "$generation_one" "$generation_two" &&
      live_is_generation_two "$generation_two" &&
      pass generation_two_state "generation two is selected, rooted, and live; generation one remains retained"
    ;;
  *)
    usage
    exit 2
    ;;
esac
