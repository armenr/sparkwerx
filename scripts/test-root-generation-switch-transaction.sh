#!/usr/bin/env bash
set -uo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  printf '%s\n' \
    "Run this isolated test as root: sudo ./scripts/test-root-generation-switch-transaction.sh" >&2
  exit 1
fi

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir" || exit 1

nix_bin=/nix/var/nix/profiles/default/bin/nix
generation_two_root=/nix/var/nix/gcroots/dgx-setup-root-canary-generation-two-pilot

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

if [[ "$generation_one" == "$generation_two" ]]; then
  printf '%s\n' 'Refusing test: generation candidates are identical' >&2
  exit 1
fi

state_before="$(
  "$repo_dir/scripts/audit-root-canary-state.sh" \
    "$generation_one" registered-first 2>/dev/null || true
)"
if [[ "$state_before" != ACTIVE_REGISTERED_RETAINED ]]; then
  printf 'Refusing generation-switch test: expected ACTIVE_REGISTERED_RETAINED host state; observed %s\n' \
    "${state_before:-UNKNOWN}" >&2
  exit 1
fi

if [[ -e "$generation_two_root" || -L "$generation_two_root" ]]; then
  printf 'Refusing disposable test: host generation-two retention root already exists: %s\n' \
    "$generation_two_root" >&2
  exit 1
fi

# Both transaction programs and every failure injection run only inside the
# disposable Ubuntu systemd-nspawn container. On the host this helper performs
# no registration, activation, profile switch, GC-root change, daemon reload,
# service operation, boot-link change, or candidate retention.
export NIX_USER_CONF_FILES=/dev/null

"$nix_bin" \
  --store local \
  --extra-experimental-features \
  "nix-command flakes auto-allocate-uids cgroups" \
  --option auto-allocate-uids true \
  build --no-link --no-write-lock-file \
  .#checks.aarch64-linux.root-canary-generation-switch-transaction-container
build_status=$?

state_after="$(
  "$repo_dir/scripts/audit-root-canary-state.sh" \
    "$generation_one" registered-first 2>/dev/null || true
)"
if [[ "$state_after" != "$state_before" ]]; then
  printf 'Host root-manager state changed across disposable generation-switch test: before=%s after=%s\n' \
    "$state_before" "${state_after:-UNKNOWN}" >&2
  exit 1
fi

if [[ -e "$generation_two_root" || -L "$generation_two_root" ]]; then
  printf 'Host generation-two retention root appeared during disposable test: %s\n' \
    "$generation_two_root" >&2
  exit 1
fi

exit "$build_status"
