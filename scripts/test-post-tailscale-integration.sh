#!/usr/bin/env bash
set -euo pipefail

# One operator-facing regression after the live Tailscale migration. The only
# root work is the disposable container lifecycle; the staged apply itself must
# remain an unprivileged orchestration of already-proven no-op transactions.

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
  'PASS|post_tailscale_integration|plan, Nix bootstrap lifecycle, Tailscale lifecycle, and live staged-apply no-op all passed'
