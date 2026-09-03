#!/usr/bin/env bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  printf '%s\n' \
    'Run this isolated test as root: sudo ./scripts/test-nix-bootstrap-lifecycle.sh' >&2
  exit 1
fi

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

nix_bin=/nix/var/nix/profiles/default/bin/nix
[[ -x "$nix_bin" ]] || {
  printf 'Expected active root-profile Nix at %s\n' "$nix_bin" >&2
  exit 1
}

# The lifecycle runs only inside a disposable Ubuntu 24.04 systemd-nspawn
# container. It removes the test driver's container-local Nix, exercises an
# injected-failure/timed-uninstall cycle, installs again, and proves the second
# operator run is a no-op. The host Nix store is used locally only to build and
# launch that isolated test derivation.
export NIX_USER_CONF_FILES=/dev/null

exec "$nix_bin" \
  --store local \
  --extra-experimental-features \
  'nix-command flakes auto-allocate-uids cgroups' \
  --option auto-allocate-uids true \
  build --no-link \
  .#checks.aarch64-linux.nix-bootstrap-lifecycle-container
