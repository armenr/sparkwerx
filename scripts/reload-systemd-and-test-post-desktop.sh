#!/usr/bin/env bash
set -euo pipefail

# Acknowledge only the exact pending systemd unit graph produced by the
# observed snapd-desktop-integration revision-396 refresh. A daemon reload
# reparses unit files; it does not restart services. This helper proves that
# every access, compute, desktop, and Snap process/state boundary below is
# byte-for-byte unchanged across that reload, then runs the normal retained
# generation-five status verifiers.

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
nix_bin=/nix/var/nix/profiles/default/bin/nix
snap_name=snapd-desktop-integration
snap_revision=396
snap_unit='snap-snapd\x2ddesktop\x2dintegration-396.mount'
snap_unit_path='/etc/systemd/system/snap-snapd\x2ddesktop\x2dintegration-396.mount'
profile_dir=/nix/var/nix/profiles/system-manager-profiles
upstream_root=/nix/var/nix/gcroots/system-manager-current
headless_root=/nix/var/nix/gcroots/dgx-setup-desktop-headless-pilot

active_units=(
  nix-daemon.socket
  tailscaled.service
  dgx-setup-canary.service
  system-manager.target
  docker.service
  dgx-dashboard-admin.service
  nvidia-persistenced.service
  dgx-headless.target
  snapd.service
  "$snap_unit"
)
inactive_units=(
  graphical.target
  gdm.service
  dgx-dashboard.service
)
tracked_units=("${active_units[@]}" "${inactive_units[@]}")

die() {
  printf 'FAIL|systemd_reload|%s\n' "$1" >&2
  exit 1
}

path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

assert_no_guard() {
  local path

  for path in \
    /var/lib/dgx-setup/desktop-switch \
    /var/lib/dgx-setup/tailscale-migration \
    /etc/systemd/system/dgx-desktop-switch-rollback.service \
    /etc/systemd/system/dgx-desktop-switch-rollback.timer \
    /etc/systemd/system/timers.target.wants/dgx-desktop-switch-rollback.timer \
    /etc/systemd/system/dgx-tailscale-migration-rollback.service \
    /etc/systemd/system/dgx-tailscale-migration-rollback.timer \
    /etc/systemd/system/timers.target.wants/dgx-tailscale-migration-rollback.timer; do
    ! path_exists "$path" || die "guarded transaction is still present: $path"
  done
}

assert_snap_refresh() {
  local observed_revision change_state

  [[ -f "$snap_unit_path" && ! -L "$snap_unit_path" ]] ||
    die "diagnosed Snap mount unit is absent or not a regular file: $snap_unit_path"
  observed_revision="$(snap list "$snap_name" 2>/dev/null | awk 'NR == 2 { print $3 }')"
  [[ "$observed_revision" == "$snap_revision" ]] ||
    die "$snap_name revision is ${observed_revision:-UNKNOWN}, expected $snap_revision"
  change_state="$(snap changes 2>/dev/null | awk -v name="$snap_name" '$0 ~ name { print $2; exit }')"
  [[ "$change_state" == Done ]] ||
    die "$snap_name refresh is ${change_state:-UNKNOWN}, expected Done"
}

assert_unit_states() {
  local expected_reload="$1" unit load active reload fragment

  for unit in "${active_units[@]}"; do
    load="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
    active="$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)"
    reload="$(systemctl show "$unit" -p NeedDaemonReload --value 2>/dev/null || true)"
    fragment="$(systemctl show "$unit" -p FragmentPath --value 2>/dev/null || true)"
    [[ "$load" == loaded && "$active" == active && -n "$fragment" ]] ||
      die "$unit is not loaded and active from a real fragment"
    [[ "$reload" == "$expected_reload" ]] ||
      die "$unit has NeedDaemonReload=${reload:-UNKNOWN}, expected $expected_reload"
  done

  for unit in "${inactive_units[@]}"; do
    load="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
    active="$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)"
    reload="$(systemctl show "$unit" -p NeedDaemonReload --value 2>/dev/null || true)"
    fragment="$(systemctl show "$unit" -p FragmentPath --value 2>/dev/null || true)"
    [[ "$load" == loaded && "$active" == inactive && -n "$fragment" ]] ||
      die "$unit is not loaded and inactive from a real fragment"
    [[ "$reload" == "$expected_reload" ]] ||
      die "$unit has NeedDaemonReload=${reload:-UNKNOWN}, expected $expected_reload"
  done
}

capture_unit_continuity() {
  systemctl show "${tracked_units[@]}" \
    -p Id -p LoadState -p ActiveState -p SubState -p Result \
    -p MainPID -p ActiveEnterTimestampMonotonic -p FragmentPath \
    --no-pager
}

capture_root_continuity() {
  readlink -- "$profile_dir/system-manager"
  readlink -- "$profile_dir/system-manager-5-link"
  readlink -- "$upstream_root"
  readlink -- "$headless_root"
  readlink -- /etc/systemd/system/default.target
  sha256sum /var/lib/system-manager/state/system-manager-state.json
  cat /proc/sys/kernel/random/boot_id
}

if [[ "$EUID" -ne 0 ]]; then
  die "run this helper with sudo"
fi
if [[ "$#" -ne 0 ]]; then
  printf 'Usage: sudo %s\n' "$(basename "$0")" >&2
  exit 2
fi

PATH=/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
NIX_USER_CONF_FILES=/dev/null
export PATH NIX_USER_CONF_FILES
cd "$repo_dir"

[[ "$(hostname -s)" == sparkle-01 ]] || die "this helper is scoped to sparkle-01"
[[ -x "$nix_bin" ]] || die "root-profile Nix is unavailable"
for command_name in awk cmp grep hostname jq readlink sed sha256sum snap systemctl timeout; do
  command -v "$command_name" >/dev/null 2>&1 ||
    die "required command is unavailable: $command_name"
done

assert_no_guard
assert_snap_refresh

generation_five="$($nix_bin --extra-experimental-features 'nix-command flakes' \
  eval --raw --no-write-lock-file \
  .#packages.aarch64-linux.root-system-desktop-headless.outPath)"
[[ "$(readlink -f -- "$profile_dir/system-manager")" == "$generation_five" ]] ||
  die "selected System Manager profile is not exact generation five"
[[ "$(readlink -- "$profile_dir/system-manager")" == system-manager-5-link ]] ||
  die "selected System Manager profile is not generation number five"
[[ "$(readlink -- "$profile_dir/system-manager-5-link")" == "$generation_five" ]] ||
  die "generation-five profile link changed"
[[ "$(readlink -- "$upstream_root")" == "$generation_five" ]] ||
  die "upstream System Manager root changed"
[[ "$(readlink -- "$headless_root")" == "$generation_five" ]] ||
  die "headless candidate root changed"
[[ "$(systemctl get-default)" == default.target ]] ||
  die "persistent default target is not the managed headless alias"

assert_unit_states yes
before_units="$(capture_unit_continuity)"
before_root="$(capture_root_continuity)"
before_identity="$(timeout 15s tailscale status --json 2>/dev/null | jq -er '.Self.ID')" ||
  die "Tailscale identity is unavailable before daemon reload"

printf 'INFO|unit_graph|acknowledging completed %s revision %s refresh\n' \
  "$snap_name" "$snap_revision"
systemctl daemon-reload || die "systemd daemon reload failed"

after_units="$(capture_unit_continuity)"
after_root="$(capture_root_continuity)"
after_identity="$(timeout 15s tailscale status --json 2>/dev/null | jq -er '.Self.ID')" ||
  die "Tailscale identity is unavailable after daemon reload"
[[ "$after_units" == "$before_units" ]] ||
  die "a tracked unit process, state, timestamp, or fragment changed across daemon reload"
[[ "$after_root" == "$before_root" ]] ||
  die "System Manager roots, state, default target, or boot ID changed across daemon reload"
[[ "$after_identity" == "$before_identity" ]] ||
  die "Tailscale node identity changed across daemon reload"
assert_snap_refresh
assert_unit_states no

system_state="$(systemctl is-system-running 2>/dev/null || true)"
[[ "$system_state" == running ]] ||
  die "systemd state is ${system_state:-UNKNOWN}, not running"
failed_units="$(systemctl --failed --no-legend --plain 2>/dev/null | sed '/^[[:space:]]*$/d' || true)"
[[ -z "$failed_units" ]] || die "systemd reports failed units after daemon reload"

desktop_status="$(./scripts/dgx-desktop status)" ||
  die "generation-five desktop verification failed after daemon reload"
printf '%s\n' "$desktop_status"
grep -Fx 'DESKTOP_STATUS=HEADLESS_CONFIRMED' <<<"$desktop_status" >/dev/null ||
  die "desktop is not exact confirmed headless generation five"

tailscale_status="$(./scripts/dgx-tailscale status)" ||
  die "Nix-managed Tailscale verification failed after daemon reload"
printf '%s\n' "$tailscale_status"
grep -Fx 'MIGRATION_STATUS=CONFIRMED_NIX_OWNED' <<<"$tailscale_status" >/dev/null ||
  die "Tailscale is not exact confirmed Nix-owned state"

printf '%s\n' \
  'PASS|daemon_reload|Snap unit graph acknowledged without a restart, state change, reboot, identity change, or desktop change' \
  'PASS|post_desktop_state|generation five/headless and inherited Nix-managed Tailscale are exact'
