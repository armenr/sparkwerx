#!/usr/bin/env bash
set -euo pipefail

# Acknowledge the exact pending systemd unit graph produced by the observed
# Thunderbird Snap refresh, prove that no protected service restarted, then
# run the root-only disposable reboot-recovery lifecycle test.

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
generation_one=/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager
generation_two=/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager
generation_three=/nix/store/w8kn2idc0ix6x1024qphv2fvmaf664d7-system-manager
expected_state=ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED

protected_units=(
  nix-daemon.service
  tailscaled.service
  gdm.service
  docker.service
  dgx-dashboard.service
  dgx-dashboard-admin.service
  nvidia-persistenced.service
)

die() {
  printf 'FAIL|%s\n' "$1" >&2
  exit 1
}

capture_continuity() {
  local unit fragment pid started

  for unit in "${protected_units[@]}"; do
    fragment="$(systemctl show "$unit" -p FragmentPath --value 2>/dev/null || true)"
    pid="$(systemctl show "$unit" -p MainPID --value 2>/dev/null || true)"
    started="$(
      systemctl show "$unit" -p ActiveEnterTimestampMonotonic --value \
        2>/dev/null || true
    )"
    [[ -n "$fragment" ]] || die "$unit has no fragment path"
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || die "$unit has no live main PID"
    [[ "$started" =~ ^[1-9][0-9]*$ ]] ||
      die "$unit has no active-enter timestamp"
    printf '%s|%s|%s|%s\n' "$unit" "$fragment" "$pid" "$started"
  done
}

assert_protected_health() {
  local expected_reload="$1" unit load active reload

  for unit in "${protected_units[@]}"; do
    load="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
    active="$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)"
    reload="$(systemctl show "$unit" -p NeedDaemonReload --value 2>/dev/null || true)"
    [[ "$load" == loaded && "$active" == active ]] ||
      die "$unit is not loaded and active"
    [[ "$reload" == "$expected_reload" ]] ||
      die "$unit has NeedDaemonReload=${reload:-UNKNOWN}, expected $expected_reload"
  done
}

if [[ "$EUID" -ne 0 ]]; then
  die 'run this helper with sudo'
fi
if [[ "$#" -ne 0 ]]; then
  printf 'Usage: sudo %s\n' "$(basename "$0")" >&2
  exit 2
fi

PATH=/nix/var/nix/profiles/default/bin:/usr/sbin:/usr/bin:/sbin:/bin
NIX_USER_CONF_FILES=/dev/null
export PATH NIX_USER_CONF_FILES
cd "$repo_dir"

[[ "$(hostname)" == sparkle-01 ]] || die 'this helper is scoped to sparkle-01'
[[ -f /etc/systemd/system/snap-thunderbird-1241.mount ]] ||
  die 'the diagnosed Thunderbird revision-1241 mount unit is absent'
thunderbird_revision="$(snap list thunderbird 2>/dev/null | awk 'NR == 2 { print $3 }')"
[[ "$thunderbird_revision" == 1241 ]] ||
  die "Thunderbird Snap revision changed from diagnosed revision 1241 to ${thunderbird_revision:-UNKNOWN}"

assert_protected_health yes
before="$(capture_continuity)"

printf 'INFO|unit_graph|acknowledging Thunderbird Snap revision 1241 and generated Netplan unit\n'
systemctl daemon-reload

after="$(capture_continuity)"
if [[ "$after" != "$before" ]]; then
  printf 'FAIL|protected service continuity changed across daemon-reload\n' >&2
  printf 'BEFORE\n%s\nAFTER\n%s\n' "$before" "$after" >&2
  exit 1
fi
assert_protected_health no

system_state="$(systemctl is-system-running 2>/dev/null || true)"
[[ "$system_state" == running ]] ||
  die "systemd state is ${system_state:-UNKNOWN}, not running"
failed_units="$(
  systemctl --failed --no-legend --plain 2>/dev/null |
    sed '/^[[:space:]]*$/d' || true
)"
[[ -z "$failed_units" ]] || die 'systemd reports failed units after daemon-reload'

observed_state="$(
  ./scripts/audit-root-canary-state.sh \
    "$generation_three" registered-third-boot \
    "$generation_one" "$generation_two" 2>/dev/null || true
)"
[[ "$observed_state" == "$expected_state" ]] ||
  die "root-manager state is ${observed_state:-UNKNOWN}, expected $expected_state"

printf 'PASS|daemon_reload|all protected processes/fragments/start-times unchanged; exact generation three retained\n'
printf 'INFO|disposable_test|starting revised reboot-recovery lifecycle test\n'
if ./scripts/test-root-reboot-recovery-transaction.sh; then
  test_status=0
else
  test_status=$?
fi
printf 'TEST_STATUS=%s\n' "$test_status"
exit "$test_status"
