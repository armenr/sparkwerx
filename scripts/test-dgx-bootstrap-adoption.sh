#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
operator=$repo_dir/scripts/dgx-setup
home_profile=$HOME/.local/state/nix/profiles/home-manager
user_profile=$HOME/.local/state/nix/profiles/profile

fail() {
  printf 'FAIL|nix_bootstrap_adoption_test|%s\n' "$1" >&2
  exit 1
}

capture_units() {
  local unit
  for unit in nix-daemon.socket nix-daemon.service tailscaled.service \
    gdm.service docker.service dgx-dashboard.service \
    dgx-dashboard-admin.service nvidia-persistenced.service; do
    systemctl show "$unit" -p Id -p LoadState -p FragmentPath -p MainPID \
      -p ActiveEnterTimestampMonotonic --value | paste -sd '|'
  done
}

capture_nix_files() {
  sha256sum /nix/nix-installer /nix/receipt.json /etc/nix/nix.conf
}

before_home="$(readlink -e "$home_profile" 2>/dev/null || true)"
before_user="$(readlink -e "$user_profile" 2>/dev/null || true)"
before_default="$(readlink -e /nix/var/nix/profiles/default 2>/dev/null || true)"
before_units="$(capture_units)"
before_files="$(capture_nix_files)"
output="$($operator bootstrap sparkle-01)"

grep -Fx \
  'PASS|nix_bootstrap|adopted exact installer 2.35.1 and healthy runtime 2.35.2' \
  <<<"$output" >/dev/null || fail 'exact installed bootstrap was not adopted'
grep -F 'HOLD|nix_features|receipt_enable_flakes=false;persistent=nix-command;' \
  <<<"$output" >/dev/null || fail 'persistent feature difference was not preserved as a hold'
grep -Fx 'PASS|nix_bootstrap|existing installation adopted with zero mutation' \
  <<<"$output" >/dev/null || fail 'zero-mutation adoption result is absent'
grep -Fx 'BOOTSTRAP_STATUS=ADOPTED' <<<"$output" >/dev/null ||
  fail 'adoption status is absent'

[[ "$(readlink -e "$home_profile" 2>/dev/null || true)" == "$before_home" ]] ||
  fail 'adoption changed the Home Manager profile'
[[ "$(readlink -e "$user_profile" 2>/dev/null || true)" == "$before_user" ]] ||
  fail 'adoption changed the user profile'
[[ "$(readlink -e /nix/var/nix/profiles/default 2>/dev/null || true)" == "$before_default" ]] ||
  fail 'adoption changed the root default profile'
[[ "$(capture_units)" == "$before_units" ]] ||
  fail 'adoption changed a protected service process or fragment'
[[ "$(capture_nix_files)" == "$before_files" ]] ||
  fail 'adoption changed an installer receipt or Nix configuration file'

printf '%s\n' \
  'PASS|nix_bootstrap_adoption_test|exact existing installer/runtime adopted with zero mutation'
