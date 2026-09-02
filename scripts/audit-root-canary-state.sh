#!/usr/bin/env bash
set -uo pipefail

candidate="${1:-}"
registration_mode="${2:-unregistered}"
other_candidate="${3:-}"
state_path=/var/lib/system-manager/state/system-manager-state.json
profile_dir=/nix/var/nix/profiles/system-manager-profiles
profile_path=$profile_dir/system-manager
generation_one_path=$profile_dir/system-manager-1-link
generation_two_path=$profile_dir/system-manager-2-link
gcroot_path=/nix/var/nix/gcroots/system-manager-current
pilot_root=/nix/var/nix/gcroots/dgx-setup-root-canary-pilot
generation_two_root=/nix/var/nix/gcroots/dgx-setup-root-canary-generation-two-pilot

case "$registration_mode" in
  unregistered | registered-first | registered-first-dual-retained | registered-second)
    ;;
  *)
    printf 'DRIFT|unknown registration mode: %s\n' "$registration_mode"
    exit 1
    ;;
esac

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
  /etc/systemd/system/default.target.wants/system-manager.target
  /etc/systemd/system/system-manager-path.service
  /etc/systemd/system/userborn.service
  /run/wrappers
  /run/current-system
)

drift() {
  printf 'DRIFT|%s\n' "$1"
  exit 1
}

path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

has_generation_link() {
  compgen -G '/nix/var/nix/profiles/system-manager-profiles/system-manager-*-link' \
    >/dev/null
}

assert_exact_first_registration() {
  local -a entries=()

  [[ -d "$profile_dir" && ! -L "$profile_dir" ]] ||
    drift "registered profile directory is missing or not a real directory"
  [[ "$(stat -c %u -- "$profile_dir" 2>/dev/null || true)" == 0 ]] ||
    drift "registered profile directory is not root-owned"

  mapfile -t entries < <(
    find "$profile_dir" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort
  )
  [[ "${#entries[@]}" -eq 2 &&
    "${entries[0]:-}" == system-manager &&
    "${entries[1]:-}" == system-manager-1-link ]] ||
    drift "registration is not the exact first-generation two-link surface"

  [[ -L "$profile_path" &&
    "$(readlink -- "$profile_path" 2>/dev/null || true)" == system-manager-1-link &&
    "$(readlink -f -- "$profile_path" 2>/dev/null || true)" == "$candidate" ]] ||
    drift "selected profile is not exact generation one"
  [[ -L "$generation_one_path" &&
    "$(readlink -- "$generation_one_path" 2>/dev/null || true)" == "$candidate" ]] ||
    drift "generation-one link does not point directly to the exact candidate"
  [[ -L "$gcroot_path" &&
    "$(readlink -- "$gcroot_path" 2>/dev/null || true)" == "$candidate" ]] ||
    drift "System Manager extra GC root does not point directly to the exact candidate"
}

assert_exact_second_registration() {
  local -a entries=()

  [[ -d "$profile_dir" && ! -L "$profile_dir" ]] ||
    drift "registered profile directory is missing or not a real directory"
  [[ "$(stat -c %u -- "$profile_dir" 2>/dev/null || true)" == 0 ]] ||
    drift "registered profile directory is not root-owned"

  mapfile -t entries < <(
    find "$profile_dir" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort
  )
  [[ "${#entries[@]}" -eq 3 &&
    "${entries[0]:-}" == system-manager &&
    "${entries[1]:-}" == system-manager-1-link &&
    "${entries[2]:-}" == system-manager-2-link ]] ||
    drift "registration is not the exact three-link generation-two surface"

  [[ -L "$profile_path" &&
    "$(readlink -- "$profile_path" 2>/dev/null || true)" == system-manager-2-link &&
    "$(readlink -f -- "$profile_path" 2>/dev/null || true)" == "$candidate" ]] ||
    drift "selected profile is not exact generation two"
  [[ -L "$generation_one_path" &&
    "$(readlink -- "$generation_one_path" 2>/dev/null || true)" == "$other_candidate" ]] ||
    drift "generation-one link does not point directly to the retained first candidate"
  [[ -L "$generation_two_path" &&
    "$(readlink -- "$generation_two_path" 2>/dev/null || true)" == "$candidate" ]] ||
    drift "generation-two link does not point directly to the active candidate"
  [[ -L "$gcroot_path" &&
    "$(readlink -- "$gcroot_path" 2>/dev/null || true)" == "$candidate" ]] ||
    drift "System Manager extra GC root does not point directly to generation two"
}

if [[ ! "$candidate" =~ ^/nix/store/[a-z0-9]{32}-system-manager$ ||
      ! -d "$candidate" ]]; then
  drift "candidate output is missing or malformed"
fi
case "$registration_mode" in
  registered-first-dual-retained | registered-second)
    [[ "$other_candidate" =~ ^/nix/store/[a-z0-9]{32}-system-manager$ &&
      -d "$other_candidate" && "$other_candidate" != "$candidate" ]] ||
      drift "other retained candidate is missing, malformed, or identical"
    ;;
  *)
    [[ -z "$other_candidate" ]] ||
      drift "an unexpected other candidate was supplied for $registration_mode"
    ;;
esac

live_artifact=0
for path in \
  "${managed_paths[@]}" "${forbidden_paths[@]}" \
  "$state_path" "$profile_dir" "$profile_path" "$gcroot_path" "$pilot_root" \
  "$generation_two_root"; do
  if path_exists "$path"; then
    live_artifact=1
    break
  fi
done
if has_generation_link; then
  live_artifact=1
fi

if [[ "$live_artifact" -eq 0 ]]; then
  printf '%s\n' INACTIVE_ABSENT
  exit 0
fi

if [[ -r "$state_path" ]] &&
  jq -e '
    . == {
      "fileTree": {"files": [], "backedUpFiles": []},
      "services": {},
      "version": 0
    }
  ' "$state_path" >/dev/null 2>&1; then
  empty_only=1
  for path in \
    "${managed_paths[@]}" "${forbidden_paths[@]}" \
    "$profile_dir" "$profile_path" "$gcroot_path" "$pilot_root" \
    "$generation_two_root"; do
    if path_exists "$path"; then
      empty_only=0
      break
    fi
  done
  if [[ "$empty_only" -eq 1 ]] && ! has_generation_link; then
    printf '%s\n' INACTIVE_EMPTY
    exit 0
  fi
fi

[[ -L "$pilot_root" ]] ||
  drift "pilot retention root is absent or not a symlink"
expected_pilot_candidate="$candidate"
if [[ "$registration_mode" == registered-second ]]; then
  expected_pilot_candidate="$other_candidate"
fi
[[ "$(readlink -- "$pilot_root" 2>/dev/null)" == "$expected_pilot_candidate" ]] ||
  drift "generation-one pilot root does not point directly to the expected candidate"

[[ -f "$state_path" && ! -L "$state_path" ]] ||
  drift "active manager state is missing or not a regular file"

case "$registration_mode" in
  unregistered)
    if path_exists "$profile_dir" || path_exists "$profile_path" ||
      path_exists "$gcroot_path" || path_exists "$generation_two_root" ||
      has_generation_link; then
      drift "generation registration exists but unregistered state was required"
    fi
    ;;
  registered-first)
    assert_exact_first_registration
    path_exists "$generation_two_root" &&
      drift "generation-two pilot root exists in exact first-generation mode"
    ;;
  registered-first-dual-retained)
    assert_exact_first_registration
    [[ -L "$generation_two_root" &&
      "$(readlink -- "$generation_two_root" 2>/dev/null || true)" == "$other_candidate" ]] ||
      drift "generation-two pilot root does not retain the exact rollback candidate"
    ;;
  registered-second)
    assert_exact_second_registration
    [[ -L "$generation_two_root" &&
      "$(readlink -- "$generation_two_root" 2>/dev/null || true)" == "$candidate" ]] ||
      drift "generation-two pilot root does not retain the exact active candidate"
    ;;
esac

jq -e '
  ((keys | sort) == ["fileTree", "services", "version"]) and
  (.version == 1) and
  ((.fileTree | keys | sort) == ["backedUpFiles", "files"]) and
  ((.fileTree.files | sort) == [
    "/etc/dgx-setup/canary",
    "/etc/systemd/system/dgx-setup-canary.service",
    "/etc/systemd/system/sysinit-reactivation.target",
    "/etc/systemd/system/system-manager.target",
    "/etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service"
  ]) and
  (.fileTree.backedUpFiles == []) and
  ((.services | keys | sort) == [
    "dgx-setup-canary.service",
    "sysinit-reactivation.target",
    "system-manager.target"
  ])
' "$state_path" >/dev/null 2>&1 ||
  drift "manager state differs from the exact five-path/three-service canary"

for path in "${forbidden_paths[@]}"; do
  path_exists "$path" && drift "forbidden root-manager path exists at $path"
done

for path in "${managed_paths[@]}"; do
  [[ -L "$path" ]] || drift "expected managed symlink is missing at $path"
done

canary_source="$(
  jq -r '.entries["dgx-setup/canary"].source // empty' \
    "$candidate/etcFiles/etcFiles.json" 2>/dev/null || true
)"
service_source="$(
  jq -r '.["dgx-setup-canary.service"].storePath // empty' \
    "$candidate/services/services.json" 2>/dev/null || true
)"
sysinit_source="$(
  jq -r '.["sysinit-reactivation.target"].storePath // empty' \
    "$candidate/services/services.json" 2>/dev/null || true
)"
manager_source="$(
  jq -r '.["system-manager.target"].storePath // empty' \
    "$candidate/services/services.json" 2>/dev/null || true
)"

expected="$(readlink -f -- "$canary_source/dgx-setup/canary" 2>/dev/null || true)"
observed="$(readlink -f -- /etc/dgx-setup/canary 2>/dev/null || true)"
[[ -n "$expected" && "$observed" == "$expected" ]] ||
  drift "canary payload does not match the exact candidate"

for pair in \
  "/etc/systemd/system/dgx-setup-canary.service|$service_source" \
  "/etc/systemd/system/sysinit-reactivation.target|$sysinit_source" \
  "/etc/systemd/system/system-manager.target|$manager_source"; do
  path="${pair%%|*}"
  expected="${pair#*|}"
  [[ -n "$expected" ]] ||
    drift "candidate unit map is incomplete for $path"
  observed="$(readlink -f -- "$path" 2>/dev/null || true)"
  expected="$(readlink -f -- "$expected" 2>/dev/null || true)"
  [[ "$observed" == "$expected" ]] ||
    drift "managed unit payload mismatch at $path"
done

observed="$(
  readlink -f -- \
    /etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service \
    2>/dev/null || true
)"
expected="$(
  readlink -f -- /etc/systemd/system/dgx-setup-canary.service 2>/dev/null || true
)"
[[ "$observed" == "$expected" ]] ||
  drift "canary target dependency does not resolve to the managed service"

grep -Fx 'host=sparkle-01' /etc/dgx-setup/canary >/dev/null 2>&1 ||
  drift "canary payload does not identify sparkle-01"

for unit in \
  dgx-setup-canary.service sysinit-reactivation.target system-manager.target; do
  [[ "$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)" == active ]] ||
    drift "managed unit $unit is not active"
  [[ "$(systemctl show "$unit" -p NeedDaemonReload --value 2>/dev/null || true)" == no ]] ||
    drift "managed unit $unit has a pending daemon reload"
done

for unit in \
  dgx-root-canary-rollback.timer \
  dgx-root-canary-rollback.service \
  dgx-root-registration-rollback.timer \
  dgx-root-registration-rollback.service \
  dgx-root-generation-switch-rollback.timer \
  dgx-root-generation-switch-rollback.service; do
  load_state="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
  [[ -z "$load_state" || "$load_state" == not-found ]] ||
    drift "transient rollback unit $unit is unexpectedly still loaded"
done

case "$registration_mode" in
  unregistered)
    printf '%s\n' ACTIVE_RETAINED
    ;;
  registered-first)
    printf '%s\n' ACTIVE_REGISTERED_RETAINED
    ;;
  registered-first-dual-retained)
    printf '%s\n' ACTIVE_REGISTERED_GENERATION_ONE_DUAL_RETAINED
    ;;
  registered-second)
    printf '%s\n' ACTIVE_REGISTERED_GENERATION_TWO_RETAINED
    ;;
esac
