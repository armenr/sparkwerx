#!/usr/bin/env bash
set -euo pipefail

# Live-host regression for the resumable front door. On this already-converged
# historical pilot, `converge` must recognize generation five, delegate to the
# proven steady-state checks, and perform no fresh-host transition or mutation.

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
operator=$repo_dir/scripts/dgx-setup
home_profile=$HOME/.local/state/nix/profiles/home-manager
user_profile=$HOME/.local/state/nix/profiles/profile

fail() {
  printf 'FAIL|dgx_setup_converge_test|%s\n' "$1" >&2
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
  find /nix/var/nix/profiles/system-manager-profiles \
    -mindepth 1 -maxdepth 1 -printf '%f|%l\n' | sort
  for path in \
    /nix/var/nix/gcroots/system-manager-current \
    /nix/var/nix/gcroots/dgx-setup-desktop-headless-pilot \
    /nix/var/nix/gcroots/dgx-setup-fleet-factory \
    /nix/var/nix/gcroots/dgx-setup-fleet-headless \
    /nix/var/nix/gcroots/dgx-setup-fleet-bootstrap-rollback; do
    if [[ -L "$path" ]]; then
      printf 'LINK|%s|%s\n' "$path" "$(readlink -- "$path")"
    else
      printf 'ABSENT|%s\n' "$path"
    fi
  done
  if [[ -e /var/lib/dgx-setup/fleet-bootstrap ||
    -L /var/lib/dgx-setup/fleet-bootstrap ]]; then
    printf 'FLEET_GUARD|PRESENT\n'
  else
    printf 'FLEET_GUARD|ABSENT\n'
  fi
  sha256sum /var/lib/system-manager/state/system-manager-state.json
  systemctl get-default
}

[[ "$EUID" -ne 0 ]] || fail 'run this live no-op regression without sudo'
[[ "$(hostname -s)" == sparkle-01 ]] || fail 'live regression is scoped to sparkle-01'
[[ -z "$(git -C "$repo_dir" status --porcelain=v1)" ]] ||
  fail 'repository must be clean'

before_home="$(readlink -e "$home_profile")"
before_user="$(readlink -e "$user_profile")"
before_nix="$(readlink -e /nix/var/nix/profiles/default)"
before_codex="$(sha256sum "$HOME/.codex/config.toml")"
before_units="$(capture_units)"
before_root="$(capture_root_state)"

output="$($operator converge sparkle-01)"
grep -Fx 'INFO|root_lifecycle|recognized retained historical sparkle-01 generation five' \
  <<<"$output" >/dev/null || fail 'converge did not recognize the historical root lane'
grep -Fx 'PASS|update|already current; no snapshot, profile generation, timer, or host state changed' \
  <<<"$output" >/dev/null || fail 'Home convergence was not an exact no-op'
grep -Fx 'APPLY_STATUS=COMPLETE' <<<"$output" >/dev/null ||
  fail 'steady-state apply did not report complete'
grep -Fx 'CONVERGE_STATUS=COMPLETE' <<<"$output" >/dev/null ||
  fail 'resumable front door did not report complete'

[[ "$(readlink -e "$home_profile")" == "$before_home" ]] || fail 'Home profile changed'
[[ "$(readlink -e "$user_profile")" == "$before_user" ]] || fail 'user profile changed'
[[ "$(readlink -e /nix/var/nix/profiles/default)" == "$before_nix" ]] ||
  fail 'Nix runtime profile changed'
[[ "$(sha256sum "$HOME/.codex/config.toml")" == "$before_codex" ]] ||
  fail 'mutable Codex configuration changed'
[[ "$(capture_units)" == "$before_units" ]] || fail 'a protected service changed'
[[ "$(capture_root_state)" == "$before_root" ]] || fail 'root or guard state changed'

printf '%s\n' \
  'PASS|dgx_setup_converge_test|historical convergence was recognized and every live layer remained an exact no-op'
