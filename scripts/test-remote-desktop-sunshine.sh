#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
if [[ "$EUID" -eq 0 ]]; then
  printf '%s\n' 'Run as your normal user; sudo is requested only for the temporary GPU test.' >&2
  exit 1
fi
if [[ "${1:-}" == inspect ]]; then
  exec ./scripts/test-remote-desktop-session.sh "$@"
fi
preset="${1:-4k120}"
if [[ "$#" -gt 1 || ! "$preset" =~ ^(1440p120|4k60|4k120)$ ]]; then
  printf '%s\n' 'Usage: ./scripts/test-remote-desktop-sunshine.sh [1440p120|4k60|4k120] | inspect SNAPSHOT_NAME' >&2
  exit 1
fi
nix --extra-experimental-features 'nix-command flakes' build --no-link --no-write-lock-file \
  .#remote-desktop-sunshine-startup-test .#remote-desktop-sunshine-startup-policy
test_bundle="$(nix --extra-experimental-features 'nix-command flakes' \
  eval --raw --no-write-lock-file .#remote-desktop-sunshine-startup-test.outPath)"
printf '%s\n' 'INFO|sunshine_test|temporary Hyprland plus Sunshine startup; no input or TCP/UDP; not a stream/FPS test'
exec sudo -- "$test_bundle/bin/dgx-remote-desktop-sunshine-startup-test" --repo "$repo_dir" --preset "$preset"
