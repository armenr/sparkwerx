#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
candidate=/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager
transaction_source=$repo_dir/scripts/root-registration-transaction.sh
transaction_sha256=86c4be22ed350782920905897d80616b3949998d2662fd04ab9d1f5c3f4078a9
nix_store_bin=/nix/var/nix/profiles/default/bin/nix-store
state_path=/var/lib/system-manager/state/system-manager-state.json
profile_dir=/nix/var/nix/profiles/system-manager-profiles
profile_path=$profile_dir/system-manager
generation_one_path=$profile_dir/system-manager-1-link
gcroot_path=/nix/var/nix/gcroots/system-manager-current
pilot_root=/nix/var/nix/gcroots/dgx-setup-root-canary-pilot
rollback_unit=dgx-root-registration-rollback

protected_units=(
  nix-daemon.service
  tailscaled.service
  gdm.service
  docker.service
  dgx-dashboard.service
  dgx-dashboard-admin.service
  nvidia-persistenced.service
)

usage() {
  printf 'Usage: sudo %s /absolute/private/registration-snapshot-directory\n' \
    "$(basename "$0")" >&2
}

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

if [[ "$EUID" -ne 0 ]]; then
  die "run this helper as root so protected-file hashes and metadata are complete"
fi
if [[ "$#" -ne 1 ]]; then
  usage
  exit 2
fi

PATH=/nix/var/nix/profiles/default/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
destination="$1"

[[ "$(hostname)" == sparkle-01 ]] ||
  die "this pilot snapshot helper is scoped to sparkle-01"
[[ -x "$nix_store_bin" ]] ||
  die "reviewed root-profile nix-store is unavailable: $nix_store_bin"
[[ -x "$transaction_source" ]] ||
  die "registration transaction program is missing or not executable"
[[ "$(sha256sum "$transaction_source" | awk '{print $1}')" == "$transaction_sha256" ]] ||
  die "registration transaction program does not match its reviewed checksum"
bash -n "$transaction_source" ||
  die "registration transaction program failed its syntax check"

case "$destination" in
  "$repo_dir"/inventory/sparkle-01/raw/system-manager-registration/*)
    ;;
  *)
    die "snapshot must be below $repo_dir/inventory/sparkle-01/raw/system-manager-registration"
    ;;
esac
if path_exists "$destination"; then
  die "snapshot destination already exists: $destination"
fi

repo_commit="$(git -C "$repo_dir" rev-parse HEAD)"
repo_status="$(git -C "$repo_dir" status --porcelain --untracked-files=all)"
[[ -z "$repo_status" ]] ||
  die "repository must be clean so the snapshot binds one committed transaction"

"$nix_store_bin" --check-validity "$candidate" >/dev/null 2>&1 ||
  die "exact candidate is not valid in the local Nix store"
[[ -x "$candidate/bin/activate" && -x "$candidate/bin/deactivate" ]] ||
  die "candidate lacks its exact activation/deactivation programs"

state_class="$("$repo_dir/scripts/audit-root-canary-state.sh" "$candidate" 2>/dev/null || true)"
[[ "$state_class" == ACTIVE_RETAINED ]] ||
  die "expected exact active-unregistered retained canary; observed ${state_class:-UNKNOWN}"
[[ -f "$state_path" && ! -L "$state_path" ]] ||
  die "live manager state is missing or not a regular file"
"$transaction_source" verify-absent "$candidate" >/dev/null ||
  die "transaction verifier rejected the unregistered pre-state"

for unit in "$rollback_unit.timer" "$rollback_unit.service"; do
  load_state="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
  [[ -z "$load_state" || "$load_state" == not-found ]] ||
    die "rollback unit name is already loaded: $unit ($load_state)"
done

for unit in "${protected_units[@]}"; do
  active="$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)"
  reload="$(systemctl show "$unit" -p NeedDaemonReload --value 2>/dev/null || true)"
  [[ "$active" == active ]] || die "$unit is not active"
  [[ "$reload" == no ]] || die "$unit has a pending daemon reload"
done
[[ "$(systemctl is-system-running 2>/dev/null || true)" == running ]] ||
  die "systemd is not in running state"
failed_units="$(systemctl --failed --no-legend --plain 2>/dev/null | sed '/^[[:space:]]*$/d' || true)"
[[ -z "$failed_units" ]] || die "systemd reports failed units"

gpu_state="$(
  nvidia-smi \
    --query-gpu=name,driver_version,pstate,temperature.gpu \
    --format=csv,noheader 2>/dev/null || true
)"
[[ -n "$gpu_state" ]] || die "nvidia-smi query failed"

status_json="$(timeout 10s tailscale status --json 2>/dev/null || true)"
prefs_json="$(timeout 10s tailscale debug prefs 2>/dev/null || true)"
jq -e . >/dev/null 2>&1 <<<"$status_json" ||
  die "Tailscale status did not return valid JSON"
jq -e . >/dev/null 2>&1 <<<"$prefs_json" ||
  die "Tailscale preferences did not return valid JSON"
backend="$(jq -r '.BackendState // "UNKNOWN"' <<<"$status_json")"
online="$(
  jq -r 'if .Self.Online == null then "UNKNOWN" else (.Self.Online | tostring) end' \
    <<<"$status_json"
)"
want_running="$(
  jq -r 'if .WantRunning == null then "UNKNOWN" else (.WantRunning | tostring) end' \
    <<<"$prefs_json"
)"
run_ssh="$(
  jq -r 'if .RunSSH == null then "UNKNOWN" else (.RunSSH | tostring) end' \
    <<<"$prefs_json"
)"
[[ "$backend" == Running && "$online" == true &&
  "$want_running" == true && "$run_ssh" == true ]] ||
  die "sanitized Tailscale health gate failed"

umask 077
install -d -m 0700 "$destination"
printf 'Snapshot creation is incomplete.\n' >"$destination/SNAPSHOT_INCOMPLETE"
install -m 0700 "$transaction_source" "$destination/root-registration-transaction.sh"

{
  printf 'schema=1\n'
  printf 'purpose=system-manager-first-registration\n'
  printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'host=sparkle-01\n'
  printf 'candidate=%s\n' "$candidate"
  printf 'repo_commit=%s\n' "$repo_commit"
  printf 'transaction_sha256=%s\n' "$transaction_sha256"
  printf 'kernel=%s\n' "$(uname -r)"
} >"$destination/context.txt"

{
  printf 'ABSENT|%s\n' "$profile_dir"
  printf 'ABSENT|%s\n' "$profile_path"
  printf 'ABSENT|%s\n' "$generation_one_path"
  printf 'ABSENT|%s\n' "$gcroot_path"
  printf 'EXACT_SYMLINK|%s|%s\n' "$pilot_root" "$candidate"
  printf 'ACTIVE_RETAINED|%s\n' "$state_path"
} >"$destination/registration.before.tsv"

install -m 0600 "$state_path" "$destination/manager-state.before.json"

sha256sum \
  /etc/nix/nix.conf \
  /etc/passwd \
  /etc/group \
  /etc/shadow \
  >"$destination/protected-files.before.sha256"

systemctl show \
  "${protected_units[@]}" \
  -p Id \
  -p LoadState \
  -p ActiveState \
  -p SubState \
  -p FragmentPath \
  -p MainPID \
  -p ActiveEnterTimestampMonotonic \
  -p NeedDaemonReload \
  --no-pager \
  >"$destination/services.before.txt"

{
  printf 'systemd=running\n'
  printf 'failed_units=0\n'
  printf 'gpu=%s\n' "$gpu_state"
  printf 'tailscale_backend=%s\n' "$backend"
  printf 'tailscale_online=%s\n' "$online"
  printf 'tailscale_want_running=%s\n' "$want_running"
  printf 'tailscale_run_ssh=%s\n' "$run_ssh"
} >"$destination/sanitized-health.before.txt"

(
  cd "$destination"
  sha256sum \
    context.txt \
    registration.before.tsv \
    manager-state.before.json \
    protected-files.before.sha256 \
    services.before.txt \
    sanitized-health.before.txt \
    root-registration-transaction.sh \
    >SHA256SUMS
)

printf 'Snapshot creation completed.\n' >"$destination/SNAPSHOT_INCOMPLETE"
mv "$destination/SNAPSHOT_INCOMPLETE" "$destination/SNAPSHOT_COMPLETE"

printf 'Snapshot created at %s\n' "$destination"
printf 'Recorded state: ACTIVE_RETAINED with exact registration surface absent.\n'
printf 'Recorded transaction: sha256:%s\n' "$transaction_sha256"
printf '%s\n' "It contains private host configuration and must remain mode 0700/root-owned."
printf '%s\n' "No registration, activation, daemon reload, or service change was performed."
