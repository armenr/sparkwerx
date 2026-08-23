#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: sudo %s /nix/store/<exact-system-manager-output> /absolute/private/snapshot-directory\n' \
    "$(basename "$0")" >&2
}

if [[ "$EUID" -ne 0 ]]; then
  printf '%s\n' "ERROR: run this helper as root so protected-file hashes and metadata are complete." >&2
  exit 1
fi

if [[ "$#" -ne 2 ]]; then
  usage
  exit 2
fi

candidate="$1"
destination="$2"
nix_store_bin=/nix/var/nix/profiles/default/bin/nix-store

if [[ "$(hostname)" != "sparkle-01" ]]; then
  printf 'ERROR: this pilot snapshot helper is scoped to sparkle-01.\n' >&2
  exit 1
fi

if [[ ! -x "$nix_store_bin" ]]; then
  printf 'ERROR: reviewed root-profile nix-store is unavailable: %s\n' "$nix_store_bin" >&2
  exit 1
fi

case "$candidate" in
  /nix/store/*-system-manager)
    ;;
  *)
    printf 'ERROR: candidate is not an exact System Manager store output: %s\n' "$candidate" >&2
    exit 1
    ;;
esac

case "$destination" in
  /*)
    ;;
  *)
    printf 'ERROR: snapshot destination must be an absolute path.\n' >&2
    exit 1
    ;;
esac

if [[ -e "$destination" || -L "$destination" ]]; then
  printf 'ERROR: snapshot destination already exists: %s\n' "$destination" >&2
  exit 1
fi

if ! "$nix_store_bin" --check-validity "$candidate" >/dev/null 2>&1; then
  printf 'ERROR: candidate is not valid in the local Nix store: %s\n' "$candidate" >&2
  exit 1
fi

if [[ ! -x "$candidate/bin/activate" || ! -x "$candidate/bin/deactivate" ]]; then
  printf 'ERROR: candidate lacks its exact activation/deactivation programs.\n' >&2
  exit 1
fi

guarded_paths=(
  /etc/dgx-setup/canary
  /etc/systemd/system/dgx-setup-canary.service
  /etc/systemd/system/sysinit-reactivation.target
  /etc/systemd/system/system-manager.target
  /etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service
  /var/lib/system-manager/state/system-manager-state.json
  /nix/var/nix/profiles/system-manager-profiles/system-manager
  /nix/var/nix/gcroots/system-manager-current
  /nix/var/nix/gcroots/dgx-setup-root-canary-pilot
)

for path in "${guarded_paths[@]}"; do
  if [[ -e "$path" || -L "$path" ]]; then
    printf 'ERROR: collision or prior activation artifact exists: %s\n' "$path" >&2
    exit 1
  fi
done

umask 077
install -d -m 0700 "$destination"
printf 'Snapshot creation is incomplete.\n' >"$destination/SNAPSHOT_INCOMPLETE"

{
  printf 'schema=1\n'
  printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'host=%s\n' "$(hostname)"
  printf 'candidate=%s\n' "$candidate"
  printf 'kernel=%s\n' "$(uname -r)"
} >"$destination/context.txt"

for path in "${guarded_paths[@]}"; do
  printf 'ABSENT|%s\n' "$path"
done >"$destination/guarded-paths.before.tsv"

tar \
  --acls \
  --xattrs \
  --numeric-owner \
  --one-file-system \
  -C / \
  -cpf "$destination/etc-systemd-system.tar" \
  etc/systemd/system

sha256sum \
  /etc/nix/nix.conf \
  /etc/passwd \
  /etc/group \
  /etc/shadow \
  >"$destination/protected-files.before.sha256"

systemctl show \
  nix-daemon.service \
  tailscaled.service \
  gdm.service \
  docker.service \
  dgx-dashboard.service \
  dgx-dashboard-admin.service \
  nvidia-persistenced.service \
  -p Id \
  -p LoadState \
  -p ActiveState \
  -p SubState \
  -p FragmentPath \
  -p NeedDaemonReload \
  --no-pager \
  >"$destination/services.before.txt"

(
  cd "$destination"
  sha256sum \
    context.txt \
    guarded-paths.before.tsv \
    etc-systemd-system.tar \
    protected-files.before.sha256 \
    services.before.txt \
    >SHA256SUMS
)

printf 'Snapshot creation completed.\n' >"$destination/SNAPSHOT_INCOMPLETE"
mv "$destination/SNAPSHOT_INCOMPLETE" "$destination/SNAPSHOT_COMPLETE"
printf 'Snapshot created at %s\n' "$destination"
printf '%s\n' "It contains private host configuration and must remain mode 0700/root-owned."
printf '%s\n' "No activation, registration, daemon reload, or service change was performed."
