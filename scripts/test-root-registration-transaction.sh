#!/usr/bin/env bash
set -uo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  printf '%s\n' \
    "Run this isolated test as root: sudo ./scripts/test-root-registration-transaction.sh" >&2
  exit 1
fi

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir" || exit 1

nix_bin=/nix/var/nix/profiles/default/bin/nix
if [[ ! -x "$nix_bin" ]]; then
  printf 'Expected active root-profile Nix at %s\n' "$nix_bin" >&2
  exit 1
fi

candidate="$(
  "$nix_bin" \
    --extra-experimental-features "nix-command flakes" \
    eval --raw --no-write-lock-file \
    .#packages.aarch64-linux.root-system-canary.outPath
)"
state_before="$(
  "$repo_dir/scripts/audit-root-canary-state.sh" "$candidate" 2>/dev/null ||
    true
)"
if [[ "$state_before" != ACTIVE_RETAINED ]]; then
  printf 'Refusing transaction test: expected ACTIVE_RETAINED host state; observed %s\n' \
    "${state_before:-UNKNOWN}" >&2
  exit 1
fi

# The exact transaction program is exercised only inside the disposable Ubuntu
# systemd-nspawn container. Failure injection is container-gated. On the host,
# this helper performs no registration, activation, profile change, GC-root
# change, daemon reload, or service operation.
export NIX_USER_CONF_FILES=/dev/null

"$nix_bin" \
  --store local \
  --extra-experimental-features \
  "nix-command flakes auto-allocate-uids cgroups" \
  --option auto-allocate-uids true \
  build --no-link --no-write-lock-file \
  .#checks.aarch64-linux.root-canary-registration-transaction-container
build_status=$?

state_after="$(
  "$repo_dir/scripts/audit-root-canary-state.sh" "$candidate" 2>/dev/null ||
    true
)"
if [[ "$state_after" != "$state_before" ]]; then
  printf 'Host root-manager state changed across disposable transaction test: before=%s after=%s\n' \
    "$state_before" "${state_after:-UNKNOWN}" >&2
  exit 1
fi

exit "$build_status"
