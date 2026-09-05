#!/usr/bin/env bash
set -euo pipefail

# One operator-facing regression for the retained Nix/Home/Tailscale/desktop
# stack. Root work is limited to exact status verification and disposable
# container lifecycles; the live apply path must remain a no-op.

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

if [[ "$EUID" -eq 0 ]]; then
  printf '%s\n' 'Run this wrapper as the declared user, not through sudo.' >&2
  exit 1
fi
if [[ -n "$(git status --porcelain=v1)" ]]; then
  printf '%s\n' 'Repository must be clean before the post-migration regression.' >&2
  exit 1
fi

./scripts/test-dgx-setup-plan.sh
sudo -- ./scripts/test-nix-bootstrap-lifecycle.sh
sudo -- ./scripts/test-tailscale-unit-lifecycle.sh
./scripts/test-dgx-setup-apply.sh

printf '%s\n' \
  'PASS|post_tailscale_integration|plan, Nix bootstrap lifecycle, Tailscale lifecycle, and complete live headless apply no-op all passed'
