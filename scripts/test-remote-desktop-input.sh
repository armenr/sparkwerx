#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
if [[ "$EUID" -eq 0 ]]; then
  printf '%s\n' 'Run as your normal user; sudo is requested only for the private GPU/input test.' >&2
  exit 1
fi
if [[ "${1:-}" == inspect ]]; then
  exec ./scripts/test-remote-desktop-session.sh "$@"
fi
preset="${1:-4k120}"
if [[ "$#" -gt 1 || ! "$preset" =~ ^(1440p120|4k60|4k120)$ ]]; then
  printf '%s\n' 'Usage: ./scripts/test-remote-desktop-input.sh [1440p120|4k60|4k120] | inspect SNAPSHOT_NAME' >&2
  exit 1
fi
nix --extra-experimental-features 'nix-command flakes' build --no-link --no-write-lock-file \
  .#remote-desktop-input-test .#remote-desktop-input-policy
test_bundle="$(nix --extra-experimental-features 'nix-command flakes' \
  eval --raw --no-write-lock-file .#remote-desktop-input-test.outPath)"
printf '%s\n' 'INFO|private_input_test|temporary Wayland keyboard/mouse; kernel input and TCP/UDP remain denied'
sudo -- "$test_bundle/bin/dgx-remote-desktop-input-test" --repo "$repo_dir" --preset "$preset"
printf '%s\n' 'PASS|private_input_test|Sunshine adapter startup and synthetic keyboard/mouse receipt passed; no Moonlight connection yet'
