#!/usr/bin/env bash
set -euo pipefail

# One operator-facing regression for the complete desktop-control boundary.
# Destructive-looking desktop transitions and reboots occur only inside the
# disposable containers. The final integration test verifies that the live
# Nix/Home/Tailscale/headless-controller stack converges as a complete no-op.

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

if [[ "$EUID" -eq 0 ]]; then
  printf '%s\n' 'Run this wrapper as the declared user, not through sudo.' >&2
  exit 1
fi
if [[ -n "$(git status --porcelain=v1)" ]]; then
  printf '%s\n' 'Repository must be clean before the desktop-stack regression.' >&2
  exit 1
fi

for test_program in \
  ./scripts/test-desktop-headless-transaction.sh \
  ./scripts/test-desktop-mode-lifecycle.sh \
  ./scripts/test-desktop-switch-lifecycle.sh; do
  printf 'INFO|desktop_stack|running %s in a disposable container\n' \
    "$test_program"
  sudo -- "$test_program"
done

./scripts/test-post-tailscale-integration.sh

printf '%s\n' \
  'PASS|desktop_stack_integration|transaction, mode lifecycle, guarded rollback, and complete headless integration passed'
