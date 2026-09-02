#!/usr/bin/env bash
set -uo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  printf '%s\n' \
    'Run this isolated test as root: sudo ./scripts/test-root-reboot-recovery-transaction.sh' >&2
  exit 1
fi

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir" || exit 1

nix_bin=/nix/var/nix/profiles/default/bin/nix
recovery_root=/nix/var/nix/gcroots/dgx-setup-root-canary-reboot-recovery-pilot
recovery_state=/var/lib/dgx-setup/reboot-recovery
recovery_service=/etc/systemd/system/dgx-root-reboot-recovery.service
recovery_timer=/etc/systemd/system/dgx-root-reboot-recovery.timer
recovery_wants=/etc/systemd/system/timers.target.wants/dgx-root-reboot-recovery.timer

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
recovery_bundle="$(
  "$nix_bin" \
    --extra-experimental-features "nix-command flakes" \
    eval --raw --no-write-lock-file \
    .#packages.aarch64-linux.root-reboot-recovery.outPath
)"

state_before="$(
  "$repo_dir/scripts/audit-root-canary-state.sh" \
    "$generation_three" registered-third-boot \
    "$generation_one" "$generation_two" 2>/dev/null || true
)"
if [[ "$state_before" != ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED ]]; then
  printf 'Refusing recovery test: expected retained generation three; observed %s\n' \
    "${state_before:-UNKNOWN}" >&2
  exit 1
fi

for path in \
  "$recovery_root" "$recovery_state" "$recovery_service" \
  "$recovery_timer" "$recovery_wants"; do
  if [[ -e "$path" || -L "$path" ]]; then
    printf 'Refusing disposable test: host recovery path exists: %s\n' "$path" >&2
    exit 1
  fi
done

for unit in dgx-root-reboot-recovery.service dgx-root-reboot-recovery.timer; do
  load_state="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
  if [[ -n "$load_state" && "$load_state" != not-found ]]; then
    printf 'Refusing disposable test: host recovery unit is loaded: %s (%s)\n' \
      "$unit" "$load_state" >&2
    exit 1
  fi
done

systemd-analyze verify \
  "$recovery_bundle/lib/systemd/system/dgx-root-reboot-recovery.service" \
  "$recovery_bundle/lib/systemd/system/dgx-root-reboot-recovery.timer" || exit 1

# All arming, unit enablement, timer firing, failure injection, rollback,
# confirmation, cleanup, and restarts occur only in the disposable Ubuntu
# systemd-nspawn container. The real host receives no recovery root, state,
# unit, daemon reload, profile change, service operation, or reboot.
export NIX_USER_CONF_FILES=/dev/null

"$nix_bin" \
  --store local \
  --extra-experimental-features \
  "nix-command flakes auto-allocate-uids cgroups" \
  --option auto-allocate-uids true \
  build --no-link --no-write-lock-file \
  .#checks.aarch64-linux.root-canary-reboot-recovery-transaction-container
build_status=$?

state_after="$(
  "$repo_dir/scripts/audit-root-canary-state.sh" \
    "$generation_three" registered-third-boot \
    "$generation_one" "$generation_two" 2>/dev/null || true
)"
if [[ "$state_after" != "$state_before" ]]; then
  printf 'Host root-manager state changed across recovery test: before=%s after=%s\n' \
    "$state_before" "${state_after:-UNKNOWN}" >&2
  exit 1
fi

for path in \
  "$recovery_root" "$recovery_state" "$recovery_service" \
  "$recovery_timer" "$recovery_wants"; do
  if [[ -e "$path" || -L "$path" ]]; then
    printf 'Host recovery path appeared during disposable test: %s\n' "$path" >&2
    exit 1
  fi
done

for unit in dgx-root-reboot-recovery.service dgx-root-reboot-recovery.timer; do
  load_state="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
  if [[ -n "$load_state" && "$load_state" != not-found ]]; then
    printf 'Host recovery unit remained loaded after disposable test: %s (%s)\n' \
      "$unit" "$load_state" >&2
    exit 1
  fi
done

exit "$build_status"
