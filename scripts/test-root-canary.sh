#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  printf '%s\n' \
    "Run this isolated test as root: sudo ./scripts/test-root-canary.sh" >&2
  exit 1
fi

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

nix_bin="/nix/var/nix/profiles/default/bin/nix"
if [[ ! -x "$nix_bin" ]]; then
  printf 'Expected active root-profile Nix at %s\n' "$nix_bin" >&2
  exit 1
fi

# The uid allocation setting is restricted, temporary, and scoped to this one
# Nix build. The derivation runs activation/deactivation only inside a disposable
# Ubuntu systemd-nspawn container; it does not activate the host configuration.
exec "$nix_bin" \
  --extra-experimental-features \
  "nix-command flakes auto-allocate-uids" \
  --option auto-allocate-uids true \
  build --no-link \
  .#checks.aarch64-linux.root-canary-container
