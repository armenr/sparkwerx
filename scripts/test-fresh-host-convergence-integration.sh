#!/usr/bin/env bash
set -euo pipefail

# One operator-facing gate for the new clone-and-converge path. All installs,
# activations, rollbacks, and reboots happen inside disposable containers. The
# only live-host operations are exact read/no-op convergence regressions.

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

if [[ "$EUID" -eq 0 ]]; then
  printf '%s\n' 'Run this integration wrapper as the declared user, not through sudo.' >&2
  exit 1
fi
if [[ -n "$(git status --porcelain=v1)" ]]; then
  printf '%s\n' 'Repository must be clean before the fresh-host convergence gate.' >&2
  exit 1
fi

printf '%s\n' 'INFO|fresh_host_gate|testing Home rollback mechanics in private temporary homes'
./scripts/test-dgx-home-rollback.sh
./scripts/test-dgx-home-update-rollback.sh

printf '%s\n' 'INFO|fresh_host_gate|testing clean Nix bootstrap and timed uninstall in a disposable container'
sudo -- ./scripts/test-nix-bootstrap-lifecycle.sh

printf '%s\n' 'INFO|fresh_host_gate|testing optional Tailscale, factory mode, headless mode, rollback, and reboots in a disposable container'
sudo -- ./scripts/test-fleet-root-bootstrap-lifecycle.sh

printf '%s\n' 'INFO|fresh_host_gate|testing the live historical host through read-only/no-op front doors'
./scripts/test-dgx-setup-plan.sh
./scripts/test-dgx-setup-apply.sh
./scripts/test-dgx-setup-converge.sh

printf '%s\n' \
  'PASS|fresh_host_convergence_integration|bootstrap, optional access, factory-to-headless lifecycle, Home rollback, and live no-op convergence passed'
