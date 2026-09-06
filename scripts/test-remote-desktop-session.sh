#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

if [[ "$EUID" -eq 0 ]]; then
  printf '%s\n' 'Run this script as your normal user; it asks sudo only when required.' >&2
  exit 1
fi
if [[ "${1:-}" == inspect ]]; then
  if [[ "$#" -ne 2 || ! "$2" =~ ^[0-9]{8}T[0-9]{6}Z-[a-f0-9]{12}$ ]]; then
    printf '%s\n' 'Usage: ./scripts/test-remote-desktop-session.sh inspect SNAPSHOT_NAME' >&2
    exit 1
  fi
  # This branch only reads a redacted error summary. It cannot start a unit,
  # touch the GPU, change the evidence permissions, or retry the failed test.
  nix --extra-experimental-features 'nix-command flakes' build --no-link --no-write-lock-file \
    .#remote-desktop-session-inspect .#remote-desktop-capture-policy
  inspect_bundle="$(nix --extra-experimental-features 'nix-command flakes' \
    eval --raw --no-write-lock-file .#remote-desktop-session-inspect.outPath)"
  exec sudo -- "$inspect_bundle/bin/dgx-remote-desktop-session-inspect" "$2"
fi
preset="${1:-4k120}"
if [[ "$#" -gt 1 || ! "$preset" =~ ^(1440p120|4k60|4k120|check-kms)$ ]]; then
  printf '%s\n' 'Usage: ./scripts/test-remote-desktop-session.sh [1440p120|4k60|4k120|check-kms]' >&2
  exit 1
fi
nix --extra-experimental-features 'nix-command flakes' build --no-link --no-write-lock-file \
  .#remote-desktop-session-test .#remote-desktop-capture-policy
test_bundle="$(nix --extra-experimental-features 'nix-command flakes' \
  eval --raw --no-write-lock-file .#remote-desktop-session-test.outPath)"

if [[ "$preset" == check-kms ]]; then
  # Only read the loaded kernel parameter. No graphics, module, or service call.
  exec sudo -- "$test_bundle/bin/dgx-remote-desktop-session-test" --check-kms
fi

# The immutable bundle contains all privileged code. No command is downloaded
# or evaluated as root. Its transient unit ends automatically if SSH disappears.
exec sudo -- "$test_bundle/bin/dgx-remote-desktop-session-test" --repo "$repo_dir" --preset "$preset"
