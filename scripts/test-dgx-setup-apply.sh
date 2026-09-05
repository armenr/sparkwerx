#!/usr/bin/env bash
set -euo pipefail

# Live-host regression for the idempotent converged-apply path. The test is
# valid only while sparkle-01 already has the exact retained Nix, Home, and
# System Manager generations: apply must verify Nix-managed Tailscale and the
# confirmed headless controller while performing no mutation.

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
operator=$repo_dir/scripts/dgx-setup
home_profile=$HOME/.local/state/nix/profiles/home-manager
user_profile=$HOME/.local/state/nix/profiles/profile

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
  readlink -- /nix/var/nix/profiles/system-manager-profiles/system-manager
  readlink -- /nix/var/nix/profiles/system-manager-profiles/system-manager-1-link
  readlink -- /nix/var/nix/profiles/system-manager-profiles/system-manager-2-link
  readlink -- /nix/var/nix/profiles/system-manager-profiles/system-manager-3-link
  readlink -- /nix/var/nix/profiles/system-manager-profiles/system-manager-4-link
  readlink -- /nix/var/nix/profiles/system-manager-profiles/system-manager-5-link
  readlink -- /nix/var/nix/gcroots/system-manager-current
  readlink -- /nix/var/nix/gcroots/dgx-setup-desktop-headless-pilot
  sha256sum /var/lib/system-manager/state/system-manager-state.json
  systemctl get-default
  systemctl show dgx-headless.target graphical.target gdm.service \
    dgx-dashboard.service -p Id -p ActiveState --value
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
before_desktop="$("$repo_dir/scripts/dgx-desktop" status)"
grep -Fx 'DESKTOP_STATUS=HEADLESS_CONFIRMED' <<<"$before_desktop" >/dev/null ||
  fail 'pre-apply desktop state is not exact confirmed headless generation five'

output="$($operator apply sparkle-01)"

grep -Fx 'PASS|apply_nix|exact bootstrap/runtime transaction converged' \
  <<<"$output" >/dev/null || fail 'Nix layer did not converge'
grep -Fx 'INFO|home_action|update-headless' <<<"$output" >/dev/null ||
  fail 'existing Home profile did not select the update/no-op lifecycle'
grep -Fx 'PASS|update|already current; no snapshot, profile generation, timer, or host state changed' \
  <<<"$output" >/dev/null || fail 'Home layer was not an exact no-op'
grep -Fx 'MIGRATION_STATUS=CONFIRMED_NIX_OWNED' \
  <<<"$output" >/dev/null || fail 'Tailscale retained state was not verified'
grep -Fx 'PASS|apply_tailscale|ownership=nix-managed;service, SSH desired state, identity continuity, and current declared generation verified; no restart performed' \
  <<<"$output" >/dev/null || fail 'Nix-managed Tailscale did not converge as a no-op'
grep -Fx 'DESKTOP_STATUS=HEADLESS_CONFIRMED' <<<"$output" >/dev/null ||
  fail 'desktop retained state was not verified'
grep -Fx 'PASS|apply_desktop|mode=headless;controller=system-manager;generation five verified; no activation, isolation, or restart performed' \
  <<<"$output" >/dev/null || fail 'headless desktop did not converge as a no-op'
grep -Fx 'APPLY_STATUS=COMPLETE' <<<"$output" >/dev/null ||
  fail 'apply did not report complete convergence'

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
after_desktop="$("$repo_dir/scripts/dgx-desktop" status)"
grep -Fx 'DESKTOP_STATUS=HEADLESS_CONFIRMED' <<<"$after_desktop" >/dev/null ||
  fail 'post-apply desktop state is not exact confirmed headless generation five'

printf '%s\n' \
  'PASS|dgx_setup_apply_test|Nix, Home, Nix-managed Tailscale, and headless generation five converged as no-ops; root, services, and mutable state stayed exact'
