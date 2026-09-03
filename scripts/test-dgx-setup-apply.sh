#!/usr/bin/env bash
set -euo pipefail

# Live-host regression for the currently idempotent staged-apply path. The
# test is valid only while sparkle-01 already has the exact retained Nix, Home,
# and System Manager generations: apply must then be a verified no-op and must
# leave the still-gated Tailscale and desktop ownership untouched.

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
operator=$repo_dir/scripts/dgx-setup
home_profile=$HOME/.local/state/nix/profiles/home-manager
user_profile=$HOME/.local/state/nix/profiles/profile
root_candidate=/nix/store/w8kn2idc0ix6x1024qphv2fvmaf664d7-system-manager
root_generation_one=/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager
root_generation_two=/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager

fail() {
  printf 'FAIL|dgx_setup_apply_test|%s\n' "$1" >&2
  exit 1
}

capture_units() {
  local unit
  for unit in tailscaled.service gdm.service docker.service \
    dgx-dashboard.service dgx-dashboard-admin.service nvidia-persistenced.service; do
    systemctl show "$unit" -p Id -p LoadState -p ActiveState -p FragmentPath \
      -p MainPID -p ActiveEnterTimestampMonotonic -p NeedDaemonReload \
      --value | paste -sd '|'
  done
}

capture_root_state() {
  "$repo_dir/scripts/audit-root-canary-state.sh" \
    "$root_candidate" registered-third-boot \
    "$root_generation_one" "$root_generation_two" activation
}

[[ "$(hostname -s)" == sparkle-01 ]] ||
  fail 'live no-op regression is scoped to sparkle-01'
[[ -z "$(git -C "$repo_dir" status --porcelain=v1)" ]] ||
  fail 'repository must be clean'

before_home="$(readlink -e "$home_profile")"
before_user="$(readlink -e "$user_profile")"
before_default="$(readlink -e /nix/var/nix/profiles/default)"
before_codex="$(sha256sum "$HOME/.codex/config.toml")"
before_units="$(capture_units)"
before_root="$(capture_root_state)"

output="$($operator apply sparkle-01)"

grep -Fx 'PASS|apply_nix|exact bootstrap/runtime transaction converged' \
  <<<"$output" >/dev/null || fail 'Nix layer did not converge'
grep -Fx 'INFO|home_action|update-headless' <<<"$output" >/dev/null ||
  fail 'existing Home profile did not select the update/no-op lifecycle'
grep -Fx 'PASS|update|already current; no snapshot, profile generation, timer, or host state changed' \
  <<<"$output" >/dev/null || fail 'Home layer was not an exact no-op'
grep -F 'HOLD|apply_tailscale|ownership=migration-pending-apt;' \
  <<<"$output" >/dev/null || fail 'Tailscale migration boundary was not retained'
grep -Fx 'HOLD|apply_desktop|host controller is not implemented; factory GNOME/GDM was not changed' \
  <<<"$output" >/dev/null || fail 'desktop boundary was not retained'
grep -Fx 'APPLY_STATUS=PARTIAL' <<<"$output" >/dev/null ||
  fail 'staged apply did not report its partial convergence honestly'

[[ "$(readlink -e "$home_profile")" == "$before_home" ]] ||
  fail 'apply changed the Home Manager profile'
[[ "$(readlink -e "$user_profile")" == "$before_user" ]] ||
  fail 'apply changed the user profile'
[[ "$(readlink -e /nix/var/nix/profiles/default)" == "$before_default" ]] ||
  fail 'apply changed the Nix runtime profile'
[[ "$(sha256sum "$HOME/.codex/config.toml")" == "$before_codex" ]] ||
  fail 'apply changed mutable Codex configuration'
[[ "$(capture_units)" == "$before_units" ]] ||
  fail 'apply changed a protected service process, fragment, or reload state'
[[ "$(capture_root_state)" == "$before_root" ]] ||
  fail 'apply changed the frozen System Manager lane'

printf '%s\n' \
  'PASS|dgx_setup_apply_test|Nix and Home converged as no-ops; Tailscale, desktop, root, services, and mutable state stayed exact'
