#!/usr/bin/env bash
set -uo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  printf '%s\n' \
    "Run this isolated test as root: sudo ./scripts/test-root-boot-persistence-transaction.sh" >&2
  exit 1
fi

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir" || exit 1

nix_bin=/nix/var/nix/profiles/default/bin/nix
generation_three_root=/nix/var/nix/gcroots/dgx-setup-root-canary-boot-persistence-pilot

if [[ ! -x "$nix_bin" ]]; then
  printf 'Expected active root-profile Nix at %s\n' "$nix_bin" >&2
  exit 1
fi

generation_one="$(
  "$nix_bin" \
    --extra-experimental-features "nix-command flakes" \
    eval --raw --no-write-lock-file \
    .#packages.aarch64-linux.root-system-canary.outPath
)"
generation_two="$(
  "$nix_bin" \
    --extra-experimental-features "nix-command flakes" \
    eval --raw --no-write-lock-file \
    .#packages.aarch64-linux.root-system-canary-generation-two.outPath
)"
generation_three="$(
  "$nix_bin" \
    --extra-experimental-features "nix-command flakes" \
    eval --raw --no-write-lock-file \
    .#packages.aarch64-linux.root-system-canary-generation-three-boot.outPath
)"

if [[ "$generation_one" == "$generation_two" ||
  "$generation_one" == "$generation_three" ||
  "$generation_two" == "$generation_three" ]]; then
  printf '%s\n' 'Refusing test: generation candidates are not distinct' >&2
  exit 1
fi

state_before="$(
  "$repo_dir/scripts/audit-root-canary-state.sh" \
    "$generation_two" registered-second "$generation_one" 2>/dev/null || true
)"
if [[ "$state_before" != ACTIVE_REGISTERED_GENERATION_TWO_RETAINED ]]; then
  printf 'Refusing boot-persistence test: expected ACTIVE_REGISTERED_GENERATION_TWO_RETAINED host state; observed %s\n' \
    "${state_before:-UNKNOWN}" >&2
  exit 1
fi

if [[ -e "$generation_three_root" || -L "$generation_three_root" ]]; then
  printf 'Refusing disposable test: host generation-three retention root already exists: %s\n' \
    "$generation_three_root" >&2
  exit 1
fi

# Every profile mutation, boot-edge activation, failure injection, and restart
# occurs only inside the disposable Ubuntu systemd-nspawn container. On the
# host this helper performs no retention, registration, activation, profile
# switch, GC-root change, daemon reload, service operation, boot link, or reboot.
export NIX_USER_CONF_FILES=/dev/null

"$nix_bin" \
  --store local \
  --extra-experimental-features \
  "nix-command flakes auto-allocate-uids cgroups" \
  --option auto-allocate-uids true \
  build --no-link --no-write-lock-file \
  .#checks.aarch64-linux.root-canary-boot-persistence-transaction-container
build_status=$?

state_after="$(
  "$repo_dir/scripts/audit-root-canary-state.sh" \
    "$generation_two" registered-second "$generation_one" 2>/dev/null || true
)"
if [[ "$state_after" != "$state_before" ]]; then
  printf 'Host root-manager state changed across disposable boot-persistence test: before=%s after=%s\n' \
    "$state_before" "${state_after:-UNKNOWN}" >&2
  exit 1
fi

if [[ -e "$generation_three_root" || -L "$generation_three_root" ]]; then
  printf 'Host generation-three retention root appeared during disposable test: %s\n' \
    "$generation_three_root" >&2
  exit 1
fi

exit "$build_status"
