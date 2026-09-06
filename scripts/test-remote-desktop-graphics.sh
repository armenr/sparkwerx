#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

nix --extra-experimental-features 'nix-command flakes' build --no-link --no-write-lock-file \
  .#remote-desktop-gpu-test .#remote-desktop-gpu-policy .#remote-desktop-session-policy
test_bundle="$(nix --extra-experimental-features 'nix-command flakes' \
  eval --raw --no-write-lock-file .#remote-desktop-gpu-test.outPath)"

for preset in smoke 1440p120 4k60 4k120; do
  "$test_bundle/bin/dgx-remote-desktop-gpu-test" --preset "$preset"
done
printf '%s\n' 'PASS|remote_desktop_graphics|offscreen NVIDIA rendering, synthetic NVENC matrix, and Hyprland config checks passed; no compositor or stream was started'
