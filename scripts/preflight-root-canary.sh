#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

failures=0

pass() {
  printf 'PASS|%s|%s\n' "$1" "$2"
}

fail() {
  printf 'FAIL|%s|%s\n' "$1" "$2"
  failures=$((failures + 1))
}

for command_name in jq nix nix-store systemctl loginctl nvidia-smi tailscale timeout; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    fail "command" "$command_name is unavailable"
  fi
done

if ((failures != 0)); then
  exit 1
fi

manifest="$(
  nix \
    --extra-experimental-features "nix-command flakes" \
    eval \
    --json \
    --offline \
    --no-write-lock-file \
    .#lib.dgxRootManagerManifest.aarch64-linux
)"

if ! jq -e '
  (.schemaVersion == 1) and
  (.system == "aarch64-linux") and
  (.manager.activated == false) and
  (.registration.performed == false) and
  (.pilotRetention.path == "/nix/var/nix/gcroots/dgx-setup-root-canary-pilot") and
  (.pilotRetention.created == false) and
  (.pilotRetention.requiredForLowLevelActivation == true) and
  (.pilotRetention.removeOnlyAfterDeactivation == true) and
  (.pilotRetention.replacesRegistration == false) and
  (.isolatedTest.result == "passed") and
  (.isolatedTest.matchesCurrent == true) and
  (.isolatedTest.hostActivationPerformed == false) and
  (.isolatedTest.hostPostflight == "clean") and
  (.policy.replaceExisting == false) and
  (.policy.startsAtBoot == false) and
  (.policy.invokesGlobalTmpfiles == false)
' >/dev/null <<<"$manifest"; then
  fail "manifest" "candidate policy or isolated-test evidence is not current"
  exit 1
fi

expected_host="$(jq -r '.hostName' <<<"$manifest")"
candidate="$(jq -r '.manager.rootOutputPath' <<<"$manifest")"
test_drv="$(jq -r '.isolatedTest.currentDrvPath' <<<"$manifest")"
test_output="$(jq -r '.isolatedTest.currentOutputPath' <<<"$manifest")"
evidence="$(jq -r '.isolatedTest.evidence' <<<"$manifest")"

printf '# DGX root-canary automatic preflight\n'
printf '# timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'INFO|candidate|%s\n' "$candidate"
printf 'INFO|isolated_test_drv|%s\n' "$test_drv"
printf 'INFO|isolated_test_output|%s\n' "$test_output"
printf 'INFO|isolated_test_evidence|%s\n' "$evidence"

if [[ "$(hostname)" == "$expected_host" ]]; then
  pass "host" "$expected_host"
else
  fail "host" "expected $expected_host; observed $(hostname)"
fi

if [[ -r "$evidence" ]]; then
  pass "evidence" "$evidence is readable"
else
  fail "evidence" "$evidence is missing"
fi

if nix-store --check-validity "$candidate" >/dev/null 2>&1; then
  pass "candidate" "$candidate is valid"
else
  fail "candidate" "$candidate is not valid in the local store"
fi

guarded_paths=(
  /etc/dgx-setup/canary
  /etc/systemd/system/dgx-setup-canary.service
  /etc/systemd/system/sysinit-reactivation.target
  /etc/systemd/system/system-manager.target
  /etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service
  /var/lib/system-manager/state/system-manager-state.json
  /nix/var/nix/profiles/system-manager-profiles/system-manager
  /nix/var/nix/gcroots/system-manager-current
  /nix/var/nix/gcroots/dgx-setup-root-canary-pilot
)

protected_absent_paths=(
  /etc/profile.d/system-manager-path.sh
  /etc/environment.d/10-system-manager.conf
  /etc/systemd/system/default.target.wants/system-manager.target
  /etc/systemd/system/system-manager-path.service
  /etc/systemd/system/userborn.service
  /run/wrappers
  /run/current-system
)

for path in "${guarded_paths[@]}" "${protected_absent_paths[@]}"; do
  if [[ -e "$path" || -L "$path" ]]; then
    fail "collision" "$path exists"
  else
    pass "collision" "$path is absent"
  fi
done

check_unit() {
  local unit="$1"
  local active reload

  active="$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)"
  reload="$(systemctl show "$unit" -p NeedDaemonReload --value 2>/dev/null || true)"
  if [[ "$active" == "active" && "$reload" == "no" ]]; then
    pass "unit" "$unit active; NeedDaemonReload=no"
  else
    fail "unit" "$unit active=${active:-UNKNOWN}; NeedDaemonReload=${reload:-UNKNOWN}"
  fi
}

for unit in \
  nix-daemon.service \
  tailscaled.service \
  gdm.service \
  docker.service \
  dgx-dashboard.service \
  dgx-dashboard-admin.service \
  nvidia-persistenced.service; do
  check_unit "$unit"
done

system_state="$(systemctl is-system-running 2>/dev/null || true)"
if [[ "$system_state" == "running" ]]; then
  pass "systemd" "system state is running"
else
  fail "systemd" "system state is ${system_state:-UNKNOWN}"
fi

gpu_state="$(
  nvidia-smi \
    --query-gpu=name,driver_version,pstate,temperature.gpu \
    --format=csv,noheader 2>/dev/null || true
)"
if [[ -n "$gpu_state" ]]; then
  pass "gpu" "$gpu_state"
else
  fail "gpu" "nvidia-smi query failed"
fi

tailscale_status_json="$(timeout 10s tailscale status --json 2>/dev/null || true)"
tailscale_prefs_json="$(timeout 10s tailscale debug prefs 2>/dev/null || true)"
tailscale_backend="UNKNOWN"
tailscale_online="UNKNOWN"
tailscale_want_running="UNKNOWN"
tailscale_run_ssh="UNKNOWN"

if jq -e . >/dev/null 2>&1 <<<"$tailscale_status_json"; then
  tailscale_backend="$(jq -r '.BackendState // "UNKNOWN"' <<<"$tailscale_status_json")"
  tailscale_online="$(
    jq -r 'if .Self.Online == null then "UNKNOWN" else (.Self.Online | tostring) end' \
      <<<"$tailscale_status_json"
  )"
fi

if jq -e . >/dev/null 2>&1 <<<"$tailscale_prefs_json"; then
  tailscale_want_running="$(
    jq -r 'if .WantRunning == null then "UNKNOWN" else (.WantRunning | tostring) end' \
      <<<"$tailscale_prefs_json"
  )"
  tailscale_run_ssh="$(
    jq -r 'if .RunSSH == null then "UNKNOWN" else (.RunSSH | tostring) end' \
      <<<"$tailscale_prefs_json"
  )"
fi

tailscale_summary="backend=$tailscale_backend;online=$tailscale_online;WantRunning=$tailscale_want_running;RunSSH=$tailscale_run_ssh"
if [[ "$tailscale_backend" == "Running" &&
      "$tailscale_online" == "true" &&
      "$tailscale_want_running" == "true" &&
      "$tailscale_run_ssh" == "true" ]]; then
  pass "tailscale" "$tailscale_summary"
else
  fail "tailscale" "$tailscale_summary"
fi

if [[ -n "${SSH_CONNECTION:-}" ]]; then
  transport="ssh"
else
  transport="non-ssh"
fi
seat_graphical="$(loginctl show-seat seat0 -p CanGraphical --value 2>/dev/null || true)"
seat_session="$(loginctl show-seat seat0 -p ActiveSession --value 2>/dev/null || true)"
printf 'INFO|recovery_evidence|transport=%s;seat0_graphical=%s;seat0_active_session=%s\n' \
  "$transport" "${seat_graphical:-UNKNOWN}" "${seat_session:-UNKNOWN}"
printf 'HOLD|manual_console_gate|A person must verify independent local console/recovery access in the activation window\n'

if ((failures != 0)); then
  printf 'FAIL|automatic_preflight|%d automatic check(s) failed; do not activate\n' "$failures"
  exit 1
fi

printf 'PASS|automatic_preflight|all machine-readable checks passed\n'
printf 'HOLD|activation|snapshot, exact pilot GC root, timed rollback, manual console confirmation, and explicit authorization are still required\n'
