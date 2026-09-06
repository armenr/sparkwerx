#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

if [[ "$EUID" -eq 0 ]]; then
  printf '%s\n' 'Run this script as your normal user; it asks sudo only for the temporary test.' >&2
  exit 1
fi
preset="${1:-4k120}"
if [[ "$#" -gt 1 || ! "$preset" =~ ^(1440p120|4k60|4k120)$ ]]; then
  printf '%s\n' 'Usage: ./scripts/test-remote-desktop-session.sh [1440p120|4k60|4k120]' >&2
  exit 1
fi
nix --extra-experimental-features 'nix-command flakes' build --no-link --no-write-lock-file \
  .#remote-desktop-session-test .#remote-desktop-capture-policy
test_bundle="$(nix --extra-experimental-features 'nix-command flakes' \
  eval --raw --no-write-lock-file .#remote-desktop-session-test.outPath)"

# The immutable bundle contains all privileged code. No command is downloaded
# or evaluated as root. Its transient unit ends automatically if SSH disappears.
exec sudo -- "$test_bundle/bin/dgx-remote-desktop-session-test" --repo "$repo_dir" --preset "$preset"
