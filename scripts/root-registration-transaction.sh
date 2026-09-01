#!/usr/bin/env bash
set -uo pipefail

# Exact first-generation registration transaction for the retained
# sparkle-01 System Manager canary. This program intentionally owns only the
# dedicated System Manager profile surface and its upstream extra GC root. It
# never activates/deactivates System Manager, touches the pilot retention root,
# adds boot linkage, reloads systemd, or changes a service.

profile_dir=/nix/var/nix/profiles/system-manager-profiles
profile_path=$profile_dir/system-manager
generation_path=$profile_dir/system-manager-1-link
gcroot_path=/nix/var/nix/gcroots/system-manager-current
pilot_root=/nix/var/nix/gcroots/dgx-setup-root-canary-pilot

PATH=/nix/var/nix/profiles/default/bin:/usr/sbin:/usr/bin:/sbin:/bin
NIX_USER_CONF_FILES=/dev/null
export PATH NIX_USER_CONF_FILES

usage() {
  printf 'Usage: %s apply-first|rollback-first|verify-first|verify-absent /nix/store/<exact-system-manager-output>\n' \
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

assert_candidate_and_retention() {
  local candidate="$1"

  [[ "$candidate" =~ ^/nix/store/[a-z0-9]{32}-system-manager$ ]] ||
    fail "candidate is not an exact System Manager store output: $candidate" || return 1
  [[ -d "$candidate" && -x "$candidate/bin/register-profile" ]] ||
    fail "candidate or its registration program is unavailable: $candidate" || return 1
  [[ -L "$pilot_root" ]] ||
    fail "pilot retention root is absent or not a symlink: $pilot_root" || return 1
  [[ "$(readlink -- "$pilot_root" 2>/dev/null || true)" == "$candidate" ]] ||
    fail "pilot retention root does not point directly to the exact candidate" || return 1
}

assert_absent_registration() {
  local candidate="$1"

  assert_candidate_and_retention "$candidate" || return 1

  # First registration deliberately starts from no profile directory at all.
  # That gives rollback one exact pre-state and avoids guessing whether an
  # existing directory or generation history belongs to another transaction.
  if path_exists "$profile_dir"; then
    fail "first-registration profile directory already exists: $profile_dir"
    return 1
  fi
  if path_exists "$gcroot_path"; then
    fail "first-registration GC-root collision exists: $gcroot_path"
    return 1
  fi

  pass registration_absent "profile directory and extra GC root are absent; pilot root retains the exact candidate"
}

profile_surface_is_exact_or_empty() {
  local candidate="$1"
  local entry name
  local -a entries=()

  if ! path_exists "$profile_dir"; then
    return 0
  fi
  [[ -d "$profile_dir" && ! -L "$profile_dir" ]] || return 1
  [[ "$(stat -c %u -- "$profile_dir" 2>/dev/null || true)" == 0 ]] || return 1

  mapfile -t entries < <(
    find "$profile_dir" -mindepth 1 -maxdepth 1 -printf '%p\n' | sort
  )
  for entry in "${entries[@]}"; do
    name="${entry##*/}"
    case "$name" in
      system-manager | system-manager-1-link)
        [[ -L "$entry" ]] || return 1
        [[ "$(readlink -f -- "$entry" 2>/dev/null || true)" == "$candidate" ]] || return 1
        ;;
      *)
        return 1
        ;;
    esac
  done
}

assert_first_registration() {
  local candidate="$1"
  local -a entries=()

  assert_candidate_and_retention "$candidate" || return 1
  [[ -d "$profile_dir" && ! -L "$profile_dir" ]] ||
    fail "profile directory is missing or not a real directory" || return 1
  [[ "$(stat -c %u -- "$profile_dir" 2>/dev/null || true)" == 0 ]] ||
    fail "profile directory is not root-owned" || return 1

  mapfile -t entries < <(
    find "$profile_dir" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort
  )
  if [[ "${#entries[@]}" -ne 2 ||
    "${entries[0]:-}" != system-manager ||
    "${entries[1]:-}" != system-manager-1-link ]]; then
    fail "profile directory is not the exact first-generation two-link surface"
    return 1
  fi

  [[ -L "$profile_path" && -L "$generation_path" ]] ||
    fail "profile or generation-one link is missing" || return 1
  [[ "$(readlink -f -- "$profile_path" 2>/dev/null || true)" == "$candidate" ]] ||
    fail "selected profile does not resolve to the exact candidate" || return 1
  [[ "$(readlink -- "$generation_path" 2>/dev/null || true)" == "$candidate" ]] ||
    fail "generation-one link does not point directly to the exact candidate" || return 1
  [[ -L "$gcroot_path" ]] ||
    fail "extra System Manager GC root is missing or not a symlink" || return 1
  [[ "$(readlink -- "$gcroot_path" 2>/dev/null || true)" == "$candidate" ]] ||
    fail "extra System Manager GC root does not point directly to the exact candidate" || return 1

  pass registration "profile, generation one, and extra GC root point to the exact candidate"
}

rollback_first_registration() {
  local candidate="$1"
  local foreign_gcroot=false

  assert_candidate_and_retention "$candidate" || return 1

  # Inspect the complete dedicated profile directory before deleting any
  # profile artifact. Unknown entries or targets are a stop condition.
  if ! profile_surface_is_exact_or_empty "$candidate"; then
    fail "profile surface contains an unknown entry or target; refusing cleanup"
    return 1
  fi

  if path_exists "$gcroot_path"; then
    if [[ -L "$gcroot_path" &&
      "$(readlink -- "$gcroot_path" 2>/dev/null || true)" == "$candidate" ]]; then
      unlink -- "$gcroot_path" || {
        fail "could not remove the exact transaction GC root"
        return 1
      }
      info rollback_gcroot "removed exact transaction root $gcroot_path"
    else
      # A collision introduced after preflight is not ours to delete. We can
      # still remove the exact profile artifacts created by this transaction.
      foreign_gcroot=true
      info rollback_gcroot "left foreign collision untouched at $gcroot_path"
    fi
  fi

  if path_exists "$profile_path"; then
    [[ -L "$profile_path" &&
      "$(readlink -f -- "$profile_path" 2>/dev/null || true)" == "$candidate" ]] || {
      fail "selected profile changed during rollback; refusing to unlink it"
      return 1
    }
    unlink -- "$profile_path" || {
      fail "could not remove the exact selected-profile link"
      return 1
    }
    info rollback_profile "removed exact selected-profile link"
  fi

  if path_exists "$generation_path"; then
    [[ -L "$generation_path" &&
      "$(readlink -- "$generation_path" 2>/dev/null || true)" == "$candidate" ]] || {
      fail "generation-one link changed during rollback; refusing to unlink it"
      return 1
    }
    unlink -- "$generation_path" || {
      fail "could not remove the exact generation-one link"
      return 1
    }
    info rollback_generation "removed exact generation-one link"
  fi

  if path_exists "$profile_dir"; then
    rmdir -- "$profile_dir" || {
      fail "profile directory is not empty after exact cleanup"
      return 1
    }
    info rollback_profile_dir "removed transaction-created empty profile directory"
  fi

  if path_exists "$profile_dir"; then
    fail "profile directory remains after rollback"
    return 1
  fi
  if [[ "$foreign_gcroot" == true ]]; then
    fail "owned profile artifacts were rolled back, but a foreign GC-root collision remains untouched"
    return 1
  fi
  if path_exists "$gcroot_path"; then
    fail "extra GC root remains after rollback"
    return 1
  fi

  pass rollback "restored the exact unregistered state; live activation and pilot root were not touched"
}

validate_test_injection() {
  local stage="${DGX_REGISTRATION_TEST_FAIL_STAGE:-}"

  [[ -n "$stage" ]] || return 0
  case "$stage" in
    upstream-gcroot-collision | after-registration)
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

apply_first_registration() {
  local candidate="$1"
  local register_status=0 rollback_status=0

  validate_test_injection || return 1
  assert_absent_registration "$candidate" || return 1

  if [[ "${DGX_REGISTRATION_TEST_FAIL_STAGE:-}" == upstream-gcroot-collision ]]; then
    # Disposable-only race fixture: upstream will advance the Nix profile and
    # then fail at its separate GC-root step. The rollback must remove only the
    # exact profile artifacts and preserve this foreign file.
    printf '%s\n' disposable-foreign-collision >"$gcroot_path" || return 1
    info injection "created disposable regular-file GC-root collision after preflight"
  fi

  if "$candidate/bin/register-profile"; then
    register_status=0
  else
    register_status=$?
  fi

  if ((register_status != 0)); then
    info registration_failure "upstream registration exited $register_status; reconciling exact partial state"
    rollback_first_registration "$candidate" || rollback_status=$?
    if ((rollback_status != 0)); then
      fail "registration failed and rollback reported an incomplete foreign state"
    else
      fail "registration failed; exact transaction state was rolled back"
    fi
    return 1
  fi

  if ! assert_first_registration "$candidate"; then
    rollback_first_registration "$candidate" || true
    fail "registration completed but exact verification failed; rollback was attempted"
    return 1
  fi

  if [[ "${DGX_REGISTRATION_TEST_FAIL_STAGE:-}" == after-registration ]]; then
    info injection "forcing failure after exact registration"
    rollback_first_registration "$candidate" || return 1
    fail "disposable post-registration failure injected after successful rollback"
    return 1
  fi

  pass transaction "first generation registered without activation, boot linkage, service change, or pilot-root removal"
}

if [[ "$EUID" -ne 0 ]]; then
  fail "run this transaction as root"
  exit 1
fi

if [[ "$#" -ne 2 ]]; then
  usage
  exit 2
fi

action="$1"
candidate="$2"

case "$action" in
  apply-first)
    apply_first_registration "$candidate"
    ;;
  rollback-first)
    rollback_first_registration "$candidate"
    ;;
  verify-first)
    assert_first_registration "$candidate"
    ;;
  verify-absent)
    assert_absent_registration "$candidate"
    ;;
  *)
    usage
    exit 2
    ;;
esac
