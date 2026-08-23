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

# Nix 2.35 does not forward experimental-feature overrides from a client to the
# daemon. Use the same local store directly as root so UID allocation and its
# required cgroup isolation can be enabled for this build without changing the
# daemon configuration or restarting it. The derivation activates/deactivates
# only inside a disposable Ubuntu systemd-nspawn container.
# Ignore root's user-specific Nix config for this deterministic one-shot command;
# the system-wide /etc/nix/nix.conf is still read. Every required experimental
# feature is supplied explicitly below and remains process-local.
export NIX_USER_CONF_FILES=/dev/null

exec "$nix_bin" \
  --store local \
  --extra-experimental-features \
  "nix-command flakes auto-allocate-uids cgroups" \
  --option auto-allocate-uids true \
  build --no-link \
  .#checks.aarch64-linux.root-canary-container
