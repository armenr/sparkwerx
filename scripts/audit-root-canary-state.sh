#!/usr/bin/env bash
set -uo pipefail

candidate="${1:-}"
state_path=/var/lib/system-manager/state/system-manager-state.json
profile_path=/nix/var/nix/profiles/system-manager-profiles/system-manager
gcroot_path=/nix/var/nix/gcroots/system-manager-current
pilot_root=/nix/var/nix/gcroots/dgx-setup-root-canary-pilot

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

if [[ ! "$candidate" =~ ^/nix/store/[a-z0-9]{32}-system-manager$ ||
      ! -d "$candidate" ]]; then
  drift "candidate output is missing or malformed"
fi

live_artifact=0
for path in \
  "${managed_paths[@]}" "${forbidden_paths[@]}" \
  "$state_path" "$profile_path" "$gcroot_path" "$pilot_root"; do
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
    "$profile_path" "$gcroot_path" "$pilot_root"; do
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
[[ "$(readlink -- "$pilot_root" 2>/dev/null)" == "$candidate" ]] ||
  drift "pilot retention root does not point directly to the exact candidate"

if path_exists "$profile_path" || path_exists "$gcroot_path" || has_generation_link; then
  drift "generation registration exists but the retained-canary authority requires it absent"
fi

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

for unit in dgx-root-canary-rollback.timer dgx-root-canary-rollback.service; do
  load_state="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
  [[ -z "$load_state" || "$load_state" == not-found ]] ||
    drift "transient rollback unit $unit is unexpectedly still loaded"
done

printf '%s\n' ACTIVE_RETAINED
