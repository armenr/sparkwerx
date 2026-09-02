#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
generation_one=/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager
generation_two=/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager
transaction_source=$repo_dir/scripts/root-generation-switch-transaction.sh
transaction_sha256=ea1a6ddc509eef4ac80aa165e29a6612d1f1b59b93681cdf813ee8b1ff6d8cdd
live_wrapper_source=$repo_dir/scripts/switch-root-canary-generation-pilot.sh
reviewed_live_wrapper_sha256=e9432ea70cc8d8705e7775b4aaddd92e5bf1d1e56c8f11d1cb537abb2c2d143c
property_parser_source=$repo_dir/scripts/systemd-snapshot-property.sh
reviewed_property_parser_sha256=1123fe7efa54c21aaa9b1609ba132bdbe3a66a50deff41da33e826eb37d332af
property_parser_test=$repo_dir/scripts/test-systemd-snapshot-property.sh
reviewed_property_parser_test_sha256=d9829ce6200752e0bb93810b2cc59cc5f137483abf4dc5a5f9ea491826585009
test_drv=/nix/store/0llhzgyraq4gr7m4agbv8wbvs7xdcql2-container-test-dgx-root-canary-generation-switch-transaction.drv
test_output=/nix/store/l5s5m3q4bd338jflq1abycajwxrfbj5v-container-test-dgx-root-canary-generation-switch-transaction
test_output_hash=sha256:01zxs9x67jgp5ifskcvkr8lihddw886ysqcqgaaw3v6dr9f18766
nix_bin=/nix/var/nix/profiles/default/bin/nix
nix_store_bin=/nix/var/nix/profiles/default/bin/nix-store
state_path=/var/lib/system-manager/state/system-manager-state.json
profile_dir=/nix/var/nix/profiles/system-manager-profiles
profile_path=$profile_dir/system-manager
generation_one_path=$profile_dir/system-manager-1-link
generation_two_path=$profile_dir/system-manager-2-link
gcroot_path=/nix/var/nix/gcroots/system-manager-current
pilot_root=/nix/var/nix/gcroots/dgx-setup-root-canary-pilot
generation_two_root=/nix/var/nix/gcroots/dgx-setup-root-canary-generation-two-pilot
rollback_unit=dgx-root-generation-switch-rollback

protected_units=(
  nix-daemon.service
  tailscaled.service
  gdm.service
  docker.service
  dgx-dashboard.service
  dgx-dashboard-admin.service
  nvidia-persistenced.service
)

managed_paths=(
  /etc/dgx-setup/canary
  /etc/systemd/system/dgx-setup-canary.service
  /etc/systemd/system/sysinit-reactivation.target
  /etc/systemd/system/system-manager.target
  /etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service
)

guarded_transient_units=(
  dgx-root-canary-rollback.timer
  dgx-root-canary-rollback.service
  dgx-root-registration-rollback.timer
  dgx-root-registration-rollback.service
  $rollback_unit.timer
  $rollback_unit.service
)

usage() {
  printf 'Usage: sudo %s /absolute/private/generation-switch-snapshot-directory\n' \
    "$(basename "$0")" >&2
}

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

require_commands() {
  local command_name

  for command_name in \
    awk bash cmp date find git grep hostname install jq mv nvidia-smi \
    readlink sed sha256sum sort stat systemctl tailscale timeout uname; do
    command -v "$command_name" >/dev/null 2>&1 ||
      die "required command is unavailable: $command_name"
  done
}

if [[ "$EUID" -ne 0 ]]; then
  die "run this helper as root so protected-file hashes and metadata are complete"
fi
if [[ "$#" -ne 1 ]]; then
  usage
  exit 2
fi

PATH=/nix/var/nix/profiles/default/bin:/usr/sbin:/usr/bin:/sbin:/bin
NIX_USER_CONF_FILES=/dev/null
export PATH NIX_USER_CONF_FILES
require_commands
cd "$repo_dir"

destination="$(readlink -m -- "$1")"
case "$destination" in
  "$repo_dir"/inventory/sparkle-01/raw/system-manager-generation-switch/*)
    ;;
  *)
    die "snapshot must be below $repo_dir/inventory/sparkle-01/raw/system-manager-generation-switch"
    ;;
esac
if path_exists "$destination"; then
  die "snapshot destination already exists: $destination"
fi

[[ "$(hostname)" == sparkle-01 ]] ||
  die "this pilot snapshot helper is scoped to sparkle-01"
[[ -x "$nix_bin" && -x "$nix_store_bin" ]] ||
  die "reviewed root-profile Nix tools are unavailable"
[[ "$($nix_bin --version)" == "nix (Nix) 2.35.2" ]] ||
  die "active root-profile Nix is not exact reviewed 2.35.2"

for program in \
  "$transaction_source" \
  "$live_wrapper_source" \
  "$property_parser_source" \
  "$property_parser_test"; do
  [[ -x "$program" ]] || die "required reviewed program is missing or not executable: $program"
  bash -n "$program" || die "program failed syntax validation: $program"
done
snapshot_program_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
live_wrapper_sha256="$(sha256sum "$live_wrapper_source" | awk '{print $1}')"
property_parser_sha256="$(sha256sum "$property_parser_source" | awk '{print $1}')"
property_parser_test_sha256="$(sha256sum "$property_parser_test" | awk '{print $1}')"
[[ "$(sha256sum "$transaction_source" | awk '{print $1}')" == "$transaction_sha256" ]] ||
  die "generation-switch transaction does not match its passed checksum"
[[ "$live_wrapper_sha256" == "$reviewed_live_wrapper_sha256" ]] ||
  die "live generation-switch wrapper differs from its reviewed checksum"
[[ "$property_parser_sha256" == "$reviewed_property_parser_sha256" ]] ||
  die "systemd snapshot parser differs from its reviewed checksum"
[[ "$property_parser_test_sha256" == "$reviewed_property_parser_test_sha256" ]] ||
  die "systemd snapshot parser test differs from its reviewed checksum"
"$property_parser_test" >/dev/null ||
  die "systemd snapshot-property regression test failed"

repo_commit="$(git -C "$repo_dir" rev-parse HEAD)"
repo_status="$(git -C "$repo_dir" status --porcelain --untracked-files=all)"
[[ -z "$repo_status" ]] ||
  die "repository must be clean so the snapshot binds one committed live-switch design"

current_generation_one="$(
  "$nix_bin" --extra-experimental-features "nix-command flakes" \
    eval --raw --no-write-lock-file \
    .#packages.aarch64-linux.root-system-canary.outPath
)"
current_generation_two="$(
  "$nix_bin" --extra-experimental-features "nix-command flakes" \
    eval --raw --no-write-lock-file \
    .#packages.aarch64-linux.root-system-canary-generation-two.outPath
)"
current_test_drv="$(
  "$nix_bin" --extra-experimental-features "nix-command flakes" \
    eval --raw --no-write-lock-file \
    .#checks.aarch64-linux.root-canary-generation-switch-transaction-container.drvPath
)"
current_test_output="$(
  "$nix_bin" --extra-experimental-features "nix-command flakes" \
    eval --raw --no-write-lock-file \
    .#checks.aarch64-linux.root-canary-generation-switch-transaction-container.outPath
)"
current_policy_drv="$(
  "$nix_bin" --extra-experimental-features "nix-command flakes" \
    eval --raw --no-write-lock-file \
    .#checks.aarch64-linux.root-manager-policy.drvPath
)"
[[ "$current_generation_one" == "$generation_one" ]] ||
  die "current flake generation one differs from the exact live candidate"
[[ "$current_generation_two" == "$generation_two" ]] ||
  die "current flake generation two differs from the passed candidate"
[[ "$current_test_drv" == "$test_drv" && "$current_test_output" == "$test_output" ]] ||
  die "current flake generation-switch test differs from the passed derivation/output"
"$nix_store_bin" --check-validity "$current_policy_drv" >/dev/null 2>&1 ||
  die "current root-manager fixed-hash policy derivation is invalid"

manifest_json="$(
  "$nix_bin" --extra-experimental-features "nix-command flakes" \
    eval --json --no-write-lock-file .#lib.dgxRootManagerManifest.aarch64-linux
)"
jq -e \
  --arg transaction_sha "$transaction_sha256" \
  --arg snapshot_sha "$snapshot_program_sha256" \
  --arg wrapper_sha "$live_wrapper_sha256" \
  --arg parser_sha "$property_parser_sha256" \
  --arg parser_test_sha "$property_parser_test_sha256" '
  .registration.guardedGenerationSwitch.status ==
    "live-pilot-designed-switch-not-authorized" and
  .registration.guardedGenerationSwitch.transactionProgram.sha256 ==
    $transaction_sha and
  .registration.guardedGenerationSwitch.hostGenerationTwoRetentionPerformed == false and
  .registration.guardedGenerationSwitch.liveSwitchPerformed == false and
  .registration.guardedGenerationSwitch.livePilot.status ==
    "repository-design-complete-not-run" and
  .registration.guardedGenerationSwitch.livePilot.snapshotProgram.sha256 ==
    $snapshot_sha and
  .registration.guardedGenerationSwitch.livePilot.switchProgram.sha256 ==
    $wrapper_sha and
  .registration.guardedGenerationSwitch.livePilot.systemdSnapshotPropertyProgram.sha256 ==
    $parser_sha and
  .registration.guardedGenerationSwitch.livePilot.systemdSnapshotPropertyTest.sha256 ==
    $parser_test_sha and
  .registration.guardedGenerationSwitch.livePilot.hostGenerationTwoRetentionPerformed == false and
  .registration.guardedGenerationSwitch.livePilot.liveSwitchPerformed == false and
  .registration.guardedGenerationSwitch.isolatedTransactionTest.result == "passed" and
  .registration.guardedGenerationSwitch.isolatedTransactionTest.matchesCurrent == true and
  .registration.guardedGenerationSwitch.isolatedTransactionTest.hostPostflight == "clean"
' >/dev/null <<<"$manifest_json" ||
  die "root-manager manifest does not retain the exact passed/no-live-switch gate"

for store_path in "$generation_one" "$generation_two" "$test_drv" "$test_output"; do
  "$nix_store_bin" --check-validity "$store_path" >/dev/null 2>&1 ||
    die "required exact Nix store path is not valid: $store_path"
done
[[ "$($nix_store_bin --query --deriver "$test_output")" == "$test_drv" ]] ||
  die "generation-switch test output has an unexpected deriver"
[[ "$($nix_store_bin --query --hash "$test_output")" == "$test_output_hash" ]] ||
  die "generation-switch test output hash differs from passed evidence"

for candidate in "$generation_one" "$generation_two"; do
  [[ -x "$candidate/bin/register-profile" && -x "$candidate/bin/activate" ]] ||
    die "candidate lacks exact registration/activation programs: $candidate"
done
generation_one_canary="$(
  jq -r '.entries["dgx-setup/canary"].source' \
    "$generation_one/etcFiles/etcFiles.json"
)/dgx-setup/canary"
generation_two_canary="$(
  jq -r '.entries["dgx-setup/canary"].source' \
    "$generation_two/etcFiles/etcFiles.json"
)/dgx-setup/canary"
grep -Fx 'registration-test-generation=2' "$generation_two_canary" >/dev/null ||
  die "generation-two canary lacks its exact harmless marker"
if grep -Fx 'registration-test-generation=2' "$generation_one_canary" >/dev/null; then
  die "generation-one canary unexpectedly contains the generation-two marker"
fi
cmp -s \
  <(grep -Fvx 'registration-test-generation=2' "$generation_two_canary") \
  "$generation_one_canary" ||
  die "candidate canary payloads differ by more than the reviewed marker"

state_class="$(
  "$repo_dir/scripts/audit-root-canary-state.sh" \
    "$generation_one" registered-first 2>/dev/null || true
)"
[[ "$state_class" == ACTIVE_REGISTERED_RETAINED ]] ||
  die "expected exact registered/live generation one; observed ${state_class:-UNKNOWN}"
if path_exists "$generation_two_root"; then
  die "host generation-two pilot root must be absent before the snapshot"
fi

for unit in "${guarded_transient_units[@]}"; do
  load_state="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
  [[ -z "$load_state" || "$load_state" == not-found ]] ||
    die "transient rollback unit is unexpectedly loaded: $unit ($load_state)"
done

for unit in "${protected_units[@]}"; do
  load_state="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
  active="$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)"
  substate="$(systemctl show "$unit" -p SubState --value 2>/dev/null || true)"
  reload="$(systemctl show "$unit" -p NeedDaemonReload --value 2>/dev/null || true)"
  fragment="$(systemctl show "$unit" -p FragmentPath --value 2>/dev/null || true)"
  main_pid="$(systemctl show "$unit" -p MainPID --value 2>/dev/null || true)"
  active_since="$(
    systemctl show "$unit" -p ActiveEnterTimestampMonotonic --value \
      2>/dev/null || true
  )"
  [[ "$load_state" == loaded ]] || die "$unit is not loaded"
  [[ "$active" == active ]] || die "$unit is not active"
  [[ -n "$substate" ]] || die "$unit has no active substate"
  [[ "$reload" == no ]] || die "$unit has a pending daemon reload"
  [[ -n "$fragment" ]] || die "$unit has no fragment path"
  [[ "$main_pid" =~ ^[1-9][0-9]*$ ]] || die "$unit has no live main PID"
  [[ "$active_since" =~ ^[1-9][0-9]*$ ]] ||
    die "$unit has no active-enter timestamp"
done
[[ "$(systemctl is-system-running 2>/dev/null || true)" == running ]] ||
  die "systemd is not in running state"
failed_units="$(
  systemctl --failed --no-legend --plain 2>/dev/null |
    sed '/^[[:space:]]*$/d' || true
)"
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
install -m 0700 \
  "$transaction_source" \
  "$destination/root-generation-switch-transaction.sh"
install -m 0700 \
  "$property_parser_source" \
  "$destination/systemd-snapshot-property.sh"

{
  printf 'schema=1\n'
  printf 'purpose=system-manager-generation-switch\n'
  printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'host=sparkle-01\n'
  printf 'generation_one=%s\n' "$generation_one"
  printf 'generation_two=%s\n' "$generation_two"
  printf 'repo_commit=%s\n' "$repo_commit"
  printf 'root_policy_drv=%s\n' "$current_policy_drv"
  printf 'transaction_sha256=%s\n' "$transaction_sha256"
  printf 'snapshot_program_sha256=%s\n' "$snapshot_program_sha256"
  printf 'live_wrapper_sha256=%s\n' "$live_wrapper_sha256"
  printf 'property_parser_sha256=%s\n' "$property_parser_sha256"
  printf 'property_parser_test_sha256=%s\n' "$property_parser_test_sha256"
  printf 'test_drv=%s\n' "$test_drv"
  printf 'test_output=%s\n' "$test_output"
  printf 'test_output_hash=%s\n' "$test_output_hash"
  printf 'nix_version=2.35.2\n'
  printf 'kernel=%s\n' "$(uname -r)"
} >"$destination/context.txt"

{
  printf 'EXACT_DIRECTORY|%s\n' "$profile_dir"
  printf 'EXACT_SYMLINK|%s|system-manager-1-link|%s\n' \
    "$profile_path" "$generation_one"
  printf 'EXACT_SYMLINK|%s|%s|%s\n' \
    "$generation_one_path" "$generation_one" "$generation_one"
  printf 'ABSENT|%s\n' "$generation_two_path"
  printf 'EXACT_SYMLINK|%s|%s|%s\n' \
    "$gcroot_path" "$generation_one" "$generation_one"
  printf 'EXACT_SYMLINK|%s|%s|%s\n' \
    "$pilot_root" "$generation_one" "$generation_one"
  printf 'ABSENT|%s\n' "$generation_two_root"
  printf 'ACTIVE_REGISTERED_RETAINED|%s\n' "$state_path"
} >"$destination/registration.before.tsv"

for path in "${managed_paths[@]}"; do
  printf 'EXACT_SYMLINK|%s|%s\n' "$path" "$(readlink -f -- "$path")"
done >"$destination/managed-links.before.tsv"

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
    managed-links.before.tsv \
    manager-state.before.json \
    protected-files.before.sha256 \
    services.before.txt \
    sanitized-health.before.txt \
    root-generation-switch-transaction.sh \
    systemd-snapshot-property.sh \
    >SHA256SUMS
)

printf 'Snapshot creation completed.\n' >"$destination/SNAPSHOT_INCOMPLETE"
mv "$destination/SNAPSHOT_INCOMPLETE" "$destination/SNAPSHOT_COMPLETE"

printf 'Snapshot created at %s\n' "$destination"
printf '%s\n' \
  'Recorded state: exact registered/live generation one; generation-two host root absent.' \
  "Recorded transaction: sha256:$transaction_sha256" \
  "Recorded passed test: $test_drv" \
  'It contains private host configuration and must remain mode 0700/root-owned.' \
  'No candidate retention, registration, activation, daemon reload, or service change was performed.'
