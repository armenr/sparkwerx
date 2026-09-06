#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

unit_snapshot() {
  systemctl show \
    tailscaled.service gdm.service dgx-headless.target \
    docker.service dgx-dashboard.service dgx-dashboard-admin.service \
    nvidia-persistenced.service \
    -p Id -p ActiveState -p SubState -p MainPID \
    -p ExecMainStartTimestampMonotonic -p FragmentPath -p NeedDaemonReload
}

before="$(unit_snapshot)"
profile_before="$(readlink -f /nix/var/nix/profiles/system-manager-profiles/system-manager || true)"
python3 -m unittest discover -s dev -p test_remote_desktop.py
nix --extra-experimental-features 'nix-command flakes' build --no-link --no-write-lock-file \
  .#remote-desktop-policy .#remote-desktop-network-test .#sunshine
test_bundle="$(nix --extra-experimental-features 'nix-command flakes' \
  eval --raw --no-write-lock-file .#remote-desktop-network-test.outPath)"

printf '%s\n' 'INFO|network_test|TCP/UDP and IPv4/IPv6 rejection checks run only in disposable network namespaces'
# Sudo is only for creating private network namespaces, never host deployment.
test_status=0
sudo "$test_bundle/bin/dgx-remote-desktop-network-test" || test_status=$?

after="$(unit_snapshot)"
profile_after="$(readlink -f /nix/var/nix/profiles/system-manager-profiles/system-manager || true)"
[[ "$before" == "$after" && "$profile_before" == "$profile_after" ]] || {
  printf '%s\n' 'FAIL|remote_desktop_preparation|live services or root profile changed during the test' >&2
  exit 1
}
[[ "$test_status" -eq 0 ]] || exit "$test_status"
printf '%s\n' 'PASS|remote_desktop_preparation|selection, package build, network rules, and host non-mutation verified; capture/streaming still untested'
