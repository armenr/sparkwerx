#!/usr/bin/env bash
set -uo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  printf '%s\n' \
    "Run this isolated test as root: sudo ./scripts/test-root-registration.sh" >&2
  exit 1
fi

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir" || exit 1

nix_bin="/nix/var/nix/profiles/default/bin/nix"
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
case "$state_before" in
  ACTIVE_RETAINED | INACTIVE_ABSENT | INACTIVE_EMPTY)
    ;;
  *)
    printf 'Refusing registration test: unsafe preflight state: %s\n' \
      "${state_before:-UNKNOWN}" >&2
    exit 1
    ;;
esac

# This uses the same root-local, process-scoped uid-range/cgroup path as the
# already reviewed activation test. Registration, generation switching, and
# activation occur only inside the disposable Ubuntu systemd-nspawn container.
# The live host registration paths, manager state, units, and exact bounded
# invariants are checked before and after and must remain in the same safe class.
export NIX_USER_CONF_FILES=/dev/null

"$nix_bin" \
  --store local \
  --extra-experimental-features \
  "nix-command flakes auto-allocate-uids cgroups" \
  --option auto-allocate-uids true \
  build --no-link --no-write-lock-file \
  .#checks.aarch64-linux.root-canary-registration-container
build_status=$?

state_after="$(
  "$repo_dir/scripts/audit-root-canary-state.sh" "$candidate" 2>/dev/null ||
    true
)"
if [[ "$state_after" != "$state_before" ]]; then
  printf 'Host root-manager state changed across disposable test: before=%s after=%s\n' \
    "$state_before" "${state_after:-UNKNOWN}" >&2
  exit 1
fi

exit "$build_status"
