#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
planner=$repo_dir/scripts/dgx-setup
home_profile=$HOME/.local/state/nix/profiles/home-manager
user_profile=$HOME/.local/state/nix/profiles/profile

fail() {
  printf 'FAIL|dgx_setup_plan_test|%s\n' "$1" >&2
  exit 1
}

capture_units() {
  local unit
  for unit in tailscaled.service gdm.service docker.service \
    dgx-dashboard.service dgx-dashboard-admin.service nvidia-persistenced.service; do
    systemctl show "$unit" -p Id -p FragmentPath -p MainPID \
      -p ActiveEnterTimestampMonotonic --value | paste -sd '|'
  done
}

before_home="$(readlink -e "$home_profile" 2>/dev/null || true)"
before_user="$(readlink -e "$user_profile" 2>/dev/null || true)"
before_units="$(capture_units)"
output="$($planner plan sparkle-01)"

grep -Fx 'INFO|declared_system|aarch64-linux' <<<"$output" >/dev/null ||
  fail 'plan omitted the declared ARM64 system'
grep -Fx 'INFO|fleet_base|enabled;ncdu,lazydocker,devbox' <<<"$output" >/dev/null ||
  fail 'plan omitted the exact fleet base'
grep -Fx 'INFO|tailscale|selected=true;ssh_desired=true;ownership=nix-managed' \
  <<<"$output" >/dev/null || fail 'plan omitted the explicit Tailscale role'
grep -F 'PASS|tailscale_apply|ownership=nix-managed;installed=1.102.3;' \
  <<<"$output" >/dev/null || fail 'plan did not verify the live Nix-managed Tailscale role'
grep -F 'PASS|nix_bootstrap|adopt exact official installer 2.35.1;' \
  <<<"$output" >/dev/null || fail 'plan did not verify the exact installer'
grep -F 'CURRENT|home|candidate=' <<<"$output" >/dev/null ||
  fail 'plan did not classify the exact live Home candidate'
grep -Fx 'PLAN_STATUS=PARTIAL_READY' <<<"$output" >/dev/null ||
  fail 'plan did not expose its remaining role gates'
! grep -q 'DGX_SERIAL_NUMBER=' <<<"$output" ||
  fail 'plan exposed the host serial number'

if "$planner" plan does-not-exist >/dev/null 2>&1; then
  fail 'unknown host declaration was accepted'
fi

[[ "$(readlink -e "$home_profile" 2>/dev/null || true)" == "$before_home" ]] ||
  fail 'plan changed the Home Manager profile'
[[ "$(readlink -e "$user_profile" 2>/dev/null || true)" == "$before_user" ]] ||
  fail 'plan changed the user profile'
[[ "$(capture_units)" == "$before_units" ]] ||
  fail 'plan changed a protected service process or fragment'

printf 'PASS|dgx_setup_plan_test|declaration, bootstrap adoption, Nix-managed Tailscale, remaining role gates, privacy, and zero-mutation checks passed\n'
