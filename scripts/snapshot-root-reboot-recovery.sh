#!/usr/bin/env bash
set -euo pipefail

# Capture the exact live generation-three/pre-reboot state used to authorize
# persistent recovery arming. This helper is read-only with respect to System
# Manager and systemd; its only write is the private snapshot directory.

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
snapshot_source=$repo_dir/scripts/snapshot-root-reboot-recovery.sh
pilot_source=$repo_dir/scripts/root-reboot-recovery-pilot.sh
operator_source=$repo_dir/scripts/dgx-recovery
property_parser_source=$repo_dir/scripts/systemd-snapshot-property.sh
property_parser_test=$repo_dir/scripts/test-systemd-snapshot-property.sh
generation_one=/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager
generation_two=/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager
generation_three=/nix/store/w8kn2idc0ix6x1024qphv2fvmaf664d7-system-manager
recovery_bundle=/nix/store/wpikhcgj77ws90j4ivdp3498mlmffyax-dgx-root-reboot-recovery
recovery_bundle_drv=/nix/store/h4qaivg6jpf1fbgz8v8dmdi0j3xmgmps-dgx-root-reboot-recovery.drv
recovery_audit=/nix/store/skzn5n9f2ld8lji3ccvpfjmy6r0nk1bw-audit-root-canary-state.sh
recovery_transaction_sha256=b1f04f39169cc000b5a532545439693bafd9d6c62d0190e9aac2c231394a6be9
recovery_audit_sha256=19cac3ba416dc3705c9dc1a996afb82840e8f4bc2d657a78f969f3f42cfddb12
test_drv=/nix/store/jqmx45mxqqz34d4yjh3186xadb2ai6qx-container-test-dgx-root-canary-reboot-recovery-transaction.drv
test_output=/nix/store/p0ywhqdf58h5r83z1pah7arba4rqr0ka-container-test-dgx-root-canary-reboot-recovery-transaction
test_output_hash=sha256:0v7i51bmpjghm8v3cly7i82j3ysvk3in17s5av2465wy3zhzmgp8
nix_bin=/nix/var/nix/profiles/default/bin/nix
nix_store_bin=/nix/var/nix/profiles/default/bin/nix-store
state_path=/var/lib/system-manager/state/system-manager-state.json
profile_dir=/nix/var/nix/profiles/system-manager-profiles
profile_path=$profile_dir/system-manager
generation_one_path=$profile_dir/system-manager-1-link
generation_two_path=$profile_dir/system-manager-2-link
generation_three_path=$profile_dir/system-manager-3-link
gcroot_path=/nix/var/nix/gcroots/system-manager-current
generation_one_root=/nix/var/nix/gcroots/dgx-setup-root-canary-pilot
generation_two_root=/nix/var/nix/gcroots/dgx-setup-root-canary-generation-two-pilot
generation_three_root=/nix/var/nix/gcroots/dgx-setup-root-canary-boot-persistence-pilot
recovery_root=/nix/var/nix/gcroots/dgx-setup-root-canary-reboot-recovery-pilot
recovery_state_dir=/var/lib/dgx-setup/reboot-recovery
recovery_service_path=/etc/systemd/system/dgx-root-reboot-recovery.service
recovery_timer_path=/etc/systemd/system/dgx-root-reboot-recovery.timer
recovery_wants_path=/etc/systemd/system/timers.target.wants/dgx-root-reboot-recovery.timer
boot_link=/etc/systemd/system/default.target.wants/system-manager.target

protected_units=(
  nix-daemon.service
  tailscaled.service
  gdm.service
  docker.service
  dgx-dashboard.service
  dgx-dashboard-admin.service
  nvidia-persistenced.service
)

protected_sockets=(
  nix-daemon.socket
)

managed_paths=(
  /etc/dgx-setup/canary
  /etc/systemd/system/dgx-setup-canary.service
  /etc/systemd/system/sysinit-reactivation.target
  /etc/systemd/system/system-manager.target
  /etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service
  "$boot_link"
)

guarded_transient_units=(
  dgx-root-canary-rollback.timer
  dgx-root-canary-rollback.service
  dgx-root-registration-rollback.timer
  dgx-root-registration-rollback.service
  dgx-root-generation-switch-rollback.timer
  dgx-root-generation-switch-rollback.service
  dgx-root-boot-persistence-rollback.timer
  dgx-root-boot-persistence-rollback.service
)

recovery_paths=(
  "$recovery_root"
  "$recovery_state_dir"
  "$recovery_service_path"
  "$recovery_timer_path"
  "$recovery_wants_path"
)

usage() {
  printf 'Usage: sudo %s /absolute/private/reboot-recovery-snapshot-directory\n' \
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
    awk bash date find git grep hostname install jq loginctl mv nvidia-smi \
    readlink sed sha256sum sort stat systemctl systemd-analyze tailscale \
    timeout tr uname; do
    command -v "$command_name" >/dev/null 2>&1 ||
      die "required command is unavailable: $command_name"
  done
}

if [[ "$EUID" -ne 0 ]]; then
  die 'run this helper as root so protected-file hashes and metadata are complete'
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
  "$repo_dir"/inventory/sparkle-01/raw/system-manager-reboot-recovery/*)
    ;;
  *)
    die "snapshot must be below $repo_dir/inventory/sparkle-01/raw/system-manager-reboot-recovery"
    ;;
esac
if path_exists "$destination"; then
  die "snapshot destination already exists: $destination"
fi

[[ "$(hostname)" == sparkle-01 ]] ||
  die 'this pilot snapshot helper is scoped to sparkle-01'
[[ -x "$nix_bin" && -x "$nix_store_bin" ]] ||
  die 'reviewed root-profile Nix tools are unavailable'
[[ "$($nix_bin --version)" == 'nix (Nix) 2.35.2' ]] ||
  die 'active root-profile Nix is not exact reviewed 2.35.2'

for program in \
  "$snapshot_source" "$pilot_source" "$operator_source" \
  "$property_parser_source" "$property_parser_test"; do
  [[ -x "$program" ]] ||
    die "required reviewed program is missing or not executable: $program"
  bash -n "$program" || die "program failed syntax validation: $program"
done
"$property_parser_test" >/dev/null ||
  die 'systemd snapshot-property regression test failed'

snapshot_sha256="$(sha256sum "$snapshot_source" | awk '{print $1}')"
pilot_sha256="$(sha256sum "$pilot_source" | awk '{print $1}')"
operator_sha256="$(sha256sum "$operator_source" | awk '{print $1}')"
property_parser_sha256="$(sha256sum "$property_parser_source" | awk '{print $1}')"
property_parser_test_sha256="$(sha256sum "$property_parser_test" | awk '{print $1}')"

repo_commit="$(git -C "$repo_dir" rev-parse HEAD)"
repo_status="$(git -C "$repo_dir" status --porcelain --untracked-files=all)"
[[ -z "$repo_status" ]] ||
  die 'repository must be clean so the snapshot binds one committed recovery design'

current_generation_one="$($nix_bin --extra-experimental-features 'nix-command flakes' eval --raw --no-write-lock-file .#packages.aarch64-linux.root-system-canary.outPath)"
current_generation_two="$($nix_bin --extra-experimental-features 'nix-command flakes' eval --raw --no-write-lock-file .#packages.aarch64-linux.root-system-canary-generation-two.outPath)"
current_generation_three="$($nix_bin --extra-experimental-features 'nix-command flakes' eval --raw --no-write-lock-file .#packages.aarch64-linux.root-system-canary-generation-three-boot.outPath)"
current_recovery_bundle="$($nix_bin --extra-experimental-features 'nix-command flakes' eval --raw --no-write-lock-file .#packages.aarch64-linux.root-reboot-recovery.outPath)"
current_test_drv="$($nix_bin --extra-experimental-features 'nix-command flakes' eval --raw --no-write-lock-file .#checks.aarch64-linux.root-canary-reboot-recovery-transaction-container.drvPath)"
current_test_output="$($nix_bin --extra-experimental-features 'nix-command flakes' eval --raw --no-write-lock-file .#checks.aarch64-linux.root-canary-reboot-recovery-transaction-container.outPath)"
current_policy_drv="$($nix_bin --extra-experimental-features 'nix-command flakes' eval --raw --no-write-lock-file .#checks.aarch64-linux.root-manager-policy.drvPath)"

[[ "$current_generation_one" == "$generation_one" &&
  "$current_generation_two" == "$generation_two" &&
  "$current_generation_three" == "$generation_three" ]] ||
  die 'current flake candidates differ from the exact live generations'
[[ "$current_recovery_bundle" == "$recovery_bundle" ]] ||
  die 'current flake recovery bundle differs from the passed production bundle'
[[ "$current_test_drv" == "$test_drv" && "$current_test_output" == "$test_output" ]] ||
  die 'current flake recovery test differs from the passed derivation/output'

manifest_json="$($nix_bin --extra-experimental-features 'nix-command flakes' eval --json --no-write-lock-file .#lib.dgxRootManagerManifest.aarch64-linux)"
jq -e \
  --arg snapshot_sha "$snapshot_sha256" \
  --arg pilot_sha "$pilot_sha256" \
  --arg operator_sha "$operator_sha256" \
  --arg parser_sha "$property_parser_sha256" \
  --arg parser_test_sha "$property_parser_test_sha256" \
  --arg transaction_sha "$recovery_transaction_sha256" \
  --arg audit_sha "$recovery_audit_sha256" '
    .bootPersistence.status == "live-generation-three-boot-linked-retained" and
    .bootPersistence.rebootRecovery.status ==
      "live-recovery-operational-host-not-armed" and
    .bootPersistence.rebootRecovery.transactionProgram.sha256 ==
      $transaction_sha and
    .bootPersistence.rebootRecovery.postbootAuditor.sha256 == $audit_sha and
    .bootPersistence.rebootRecovery.isolatedTransactionTest.result == "passed" and
    .bootPersistence.rebootRecovery.isolatedTransactionTest.matchesCurrent == true and
    .bootPersistence.rebootRecovery.isolatedTransactionTest.hostPostflight == "clean" and
    .bootPersistence.rebootRecovery.livePilot.status ==
      "repository-design-complete-host-not-armed" and
    .bootPersistence.rebootRecovery.livePilot.snapshotProgram.sha256 ==
      $snapshot_sha and
    .bootPersistence.rebootRecovery.livePilot.pilotProgram.sha256 ==
      $pilot_sha and
    .bootPersistence.rebootRecovery.livePilot.operatorProgram.sha256 ==
      $operator_sha and
    .bootPersistence.rebootRecovery.livePilot.operatorProgram.performsReboot ==
      false and
    .bootPersistence.rebootRecovery.livePilot.systemdSnapshotPropertyProgram.sha256 ==
      $parser_sha and
    .bootPersistence.rebootRecovery.livePilot.systemdSnapshotPropertyTest.sha256 ==
      $parser_test_sha and
    .bootPersistence.rebootRecovery.livePilot.hostSnapshotCreated == true and
    .bootPersistence.rebootRecovery.livePilot.hostRecoveryArmed == false and
    .bootPersistence.rebootRecovery.livePilot.hostRebootPerformed == true
  ' >/dev/null <<<"$manifest_json" ||
  die 'root-manager manifest does not retain the exact reviewed/unarmed live-recovery gate'

for store_path in \
  "$generation_one" "$generation_two" "$generation_three" \
  "$recovery_bundle" "$recovery_bundle_drv" "$recovery_audit" \
  "$test_drv" "$test_output" "$current_policy_drv"; do
  "$nix_store_bin" --check-validity "$store_path" >/dev/null 2>&1 ||
    die "required exact Nix store path is invalid: $store_path"
done
[[ "$($nix_store_bin --query --deriver "$recovery_bundle")" == "$recovery_bundle_drv" ]] ||
  die 'production recovery bundle has an unexpected deriver'
[[ "$($nix_store_bin --query --deriver "$test_output")" == "$test_drv" ]] ||
  die 'recovery test output has an unexpected deriver'
[[ "$($nix_store_bin --query --hash "$test_output")" == "$test_output_hash" ]] ||
  die 'recovery test output hash differs from passed evidence'

systemd-analyze verify \
  "$recovery_bundle/lib/systemd/system/dgx-root-reboot-recovery.service" \
  "$recovery_bundle/lib/systemd/system/dgx-root-reboot-recovery.timer" ||
  die 'production recovery unit validation failed'

state_class="$(
  "$repo_dir/scripts/audit-root-canary-state.sh" \
    "$generation_three" registered-third-boot \
    "$generation_one" "$generation_two" 2>/dev/null || true
)"
[[ "$state_class" == ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED ]] ||
  die "expected exact live pre-reboot generation three; observed ${state_class:-UNKNOWN}"

for path in "${recovery_paths[@]}"; do
  path_exists "$path" && die "recovery path must be absent before snapshot: $path"
done
for unit in dgx-root-reboot-recovery.service dgx-root-reboot-recovery.timer; do
  load_state="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
  [[ -z "$load_state" || "$load_state" == not-found ]] ||
    die "recovery unit is unexpectedly loaded: $unit ($load_state)"
done
for unit in "${guarded_transient_units[@]}"; do
  load_state="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
  [[ -z "$load_state" || "$load_state" == not-found ]] ||
    die "transient rollback unit is unexpectedly loaded: $unit ($load_state)"
done

for unit in "${protected_units[@]}"; do
  load_state="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
  active="$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)"
  reload="$(systemctl show "$unit" -p NeedDaemonReload --value 2>/dev/null || true)"
  fragment="$(systemctl show "$unit" -p FragmentPath --value 2>/dev/null || true)"
  main_pid="$(systemctl show "$unit" -p MainPID --value 2>/dev/null || true)"
  active_since="$(systemctl show "$unit" -p ActiveEnterTimestampMonotonic --value 2>/dev/null || true)"
  [[ "$load_state" == loaded && "$active" == active && "$reload" == no ]] ||
    die "$unit is not loaded/active/reload-clean"
  [[ -n "$fragment" ]] || die "$unit has no fragment path"
  [[ "$main_pid" =~ ^[1-9][0-9]*$ ]] || die "$unit has no live main PID"
  [[ "$active_since" =~ ^[1-9][0-9]*$ ]] ||
    die "$unit has no active-enter timestamp"
done

for unit in "${protected_sockets[@]}"; do
  load_state="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
  active="$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)"
  substate="$(systemctl show "$unit" -p SubState --value 2>/dev/null || true)"
  reload="$(systemctl show "$unit" -p NeedDaemonReload --value 2>/dev/null || true)"
  fragment="$(systemctl show "$unit" -p FragmentPath --value 2>/dev/null || true)"
  result="$(systemctl show "$unit" -p Result --value 2>/dev/null || true)"
  [[ "$load_state" == loaded && "$active" == active &&
    ("$substate" == listening || "$substate" == running) &&
    "$reload" == no && "$result" == success ]] ||
    die "$unit is not loaded/active/socket-ready/reload-clean"
  [[ -n "$fragment" ]] || die "$unit has no fragment path"
done

system_state="$(systemctl is-system-running 2>/dev/null || true)"
[[ "$system_state" == running ]] ||
  die "systemd state is ${system_state:-UNKNOWN}, not running"
failed_units="$(systemctl --failed --no-legend --plain 2>/dev/null | sed '/^[[:space:]]*$/d' || true)"
[[ -z "$failed_units" ]] || die 'systemd reports failed units'
gpu_state="$(nvidia-smi --query-gpu=name,driver_version,pstate,temperature.gpu --format=csv,noheader 2>/dev/null || true)"
[[ -n "$gpu_state" ]] || die 'nvidia-smi query failed'

status_json="$(timeout 10s tailscale status --json 2>/dev/null || true)"
prefs_json="$(timeout 10s tailscale debug prefs 2>/dev/null || true)"
jq -e . >/dev/null 2>&1 <<<"$status_json" ||
  die 'Tailscale status did not return valid JSON'
jq -e . >/dev/null 2>&1 <<<"$prefs_json" ||
  die 'Tailscale preferences did not return valid JSON'
backend="$(jq -r '.BackendState // "UNKNOWN"' <<<"$status_json")"
online="$(jq -r 'if .Self.Online == null then "UNKNOWN" else (.Self.Online | tostring) end' <<<"$status_json")"
want_running="$(jq -r 'if .WantRunning == null then "UNKNOWN" else (.WantRunning | tostring) end' <<<"$prefs_json")"
run_ssh="$(jq -r 'if .RunSSH == null then "UNKNOWN" else (.RunSSH | tostring) end' <<<"$prefs_json")"
[[ "$backend" == Running && "$online" == true &&
  "$want_running" == true && "$run_ssh" == true ]] ||
  die 'sanitized Tailscale health gate failed'

seat_can_graphical="$(loginctl show-seat seat0 -p CanGraphical --value 2>/dev/null || true)"
seat_active_session="$(loginctl show-seat seat0 -p ActiveSession --value 2>/dev/null || true)"
[[ "$seat_can_graphical" == yes && -n "$seat_active_session" ]] ||
  die 'seat0 does not expose an active graphical local-console recovery session'
boot_id="$(tr -d '\n' </proc/sys/kernel/random/boot_id)"
[[ "$boot_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] ||
  die 'kernel boot ID is malformed'

umask 077
install -d -m 0700 "$destination"
printf 'Snapshot creation is incomplete.\n' >"$destination/SNAPSHOT_INCOMPLETE"
install -m 0700 "$snapshot_source" "$destination/snapshot-root-reboot-recovery.sh"
install -m 0700 "$pilot_source" "$destination/root-reboot-recovery-pilot.sh"
install -m 0700 "$property_parser_source" "$destination/systemd-snapshot-property.sh"

{
  printf 'schema=2\n'
  printf 'purpose=system-manager-first-reboot-recovery\n'
  printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'host=sparkle-01\n'
  printf 'repo_dir=%s\n' "$repo_dir"
  printf 'repo_commit=%s\n' "$repo_commit"
  printf 'generation_one=%s\n' "$generation_one"
  printf 'generation_two=%s\n' "$generation_two"
  printf 'generation_three=%s\n' "$generation_three"
  printf 'recovery_bundle=%s\n' "$recovery_bundle"
  printf 'recovery_bundle_drv=%s\n' "$recovery_bundle_drv"
  printf 'recovery_audit=%s\n' "$recovery_audit"
  printf 'recovery_transaction_sha256=%s\n' "$recovery_transaction_sha256"
  printf 'recovery_audit_sha256=%s\n' "$recovery_audit_sha256"
  printf 'snapshot_program_sha256=%s\n' "$snapshot_sha256"
  printf 'pilot_program_sha256=%s\n' "$pilot_sha256"
  printf 'operator_program_sha256=%s\n' "$operator_sha256"
  printf 'property_parser_sha256=%s\n' "$property_parser_sha256"
  printf 'property_parser_test_sha256=%s\n' "$property_parser_test_sha256"
  printf 'test_drv=%s\n' "$test_drv"
  printf 'test_output=%s\n' "$test_output"
  printf 'test_output_hash=%s\n' "$test_output_hash"
  printf 'root_policy_drv=%s\n' "$current_policy_drv"
  printf 'nix_version=2.35.2\n'
  printf 'arming_boot_id=%s\n' "$boot_id"
  printf 'manual_console_gate=required-before-arming\n'
  printf 'reboot_authorization=separate-and-not-granted-by-snapshot\n'
  printf 'kernel=%s\n' "$(uname -r)"
} >"$destination/context.txt"

{
  printf 'EXACT_DIRECTORY|%s\n' "$profile_dir"
  printf 'EXACT_SYMLINK|%s|system-manager-3-link|%s\n' "$profile_path" "$generation_three"
  printf 'EXACT_SYMLINK|%s|%s|%s\n' "$generation_one_path" "$generation_one" "$generation_one"
  printf 'EXACT_SYMLINK|%s|%s|%s\n' "$generation_two_path" "$generation_two" "$generation_two"
  printf 'EXACT_SYMLINK|%s|%s|%s\n' "$generation_three_path" "$generation_three" "$generation_three"
  printf 'EXACT_SYMLINK|%s|%s|%s\n' "$gcroot_path" "$generation_three" "$generation_three"
  printf 'EXACT_SYMLINK|%s|%s|%s\n' "$generation_one_root" "$generation_one" "$generation_one"
  printf 'EXACT_SYMLINK|%s|%s|%s\n' "$generation_two_root" "$generation_two" "$generation_two"
  printf 'EXACT_SYMLINK|%s|%s|%s\n' "$generation_three_root" "$generation_three" "$generation_three"
  printf 'EXACT_SYMLINK|%s|../system-manager.target|%s\n' \
    "$boot_link" "$(readlink -f -- "$boot_link")"
  printf 'ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED|%s\n' "$state_path"
} >"$destination/registration.before.tsv"

for path in "${managed_paths[@]}"; do
  printf 'EXACT_SYMLINK|%s|%s\n' "$path" "$(readlink -f -- "$path")"
done >"$destination/managed-links.before.tsv"

{
  for path in "${recovery_paths[@]}"; do
    printf 'ABSENT|%s\n' "$path"
  done
  printf 'NOT_FOUND|dgx-root-reboot-recovery.service\n'
  printf 'NOT_FOUND|dgx-root-reboot-recovery.timer\n'
} >"$destination/recovery.before.tsv"

install -m 0600 "$state_path" "$destination/manager-state.before.json"
sha256sum /etc/nix/nix.conf /etc/passwd /etc/group /etc/shadow \
  >"$destination/protected-files.before.sha256"

systemctl show "${protected_units[@]}" "${protected_sockets[@]}" \
  -p Id -p LoadState -p ActiveState -p SubState -p FragmentPath -p MainPID \
  -p ActiveEnterTimestampMonotonic -p NeedDaemonReload -p Result --no-pager \
  >"$destination/services.before.txt"

{
  printf 'systemd=running\n'
  printf 'failed_units=0\n'
  printf 'gpu=%s\n' "$gpu_state"
  printf 'tailscale_backend=%s\n' "$backend"
  printf 'tailscale_online=%s\n' "$online"
  printf 'tailscale_want_running=%s\n' "$want_running"
  printf 'tailscale_run_ssh=%s\n' "$run_ssh"
  printf 'nix_daemon_socket=active/%s\n' "$substate"
  printf 'seat0_can_graphical=%s\n' "$seat_can_graphical"
  printf 'seat0_active_session_present=true\n'
} >"$destination/sanitized-health.before.txt"

(
  cd "$destination"
  sha256sum \
    context.txt registration.before.tsv managed-links.before.tsv \
    recovery.before.tsv manager-state.before.json \
    protected-files.before.sha256 services.before.txt \
    sanitized-health.before.txt snapshot-root-reboot-recovery.sh \
    root-reboot-recovery-pilot.sh systemd-snapshot-property.sh \
    >SHA256SUMS
)

printf 'Snapshot creation completed.\n' >"$destination/SNAPSHOT_INCOMPLETE"
mv "$destination/SNAPSHOT_INCOMPLETE" "$destination/SNAPSHOT_COMPLETE"

snapshot_stamp="${destination##*/}"
printf 'Snapshot created at %s\n' "$destination"
printf '%s\n' \
  'Recorded state: exact registered/live boot-linked generation three; recovery surface absent.' \
  'Recorded Nix runtime: daemon active and daemon socket ready.' \
  "Recorded recovery bundle: $recovery_bundle" \
  "Recorded passed test: $test_drv" \
  'It contains private host configuration and must remain mode 0700/root-owned.' \
  'No recovery root, state, unit, daemon reload, service operation, or reboot was performed.'
printf 'I verified the local console and authorize persistent first-reboot recovery arming using snapshot %s. I understand this does not authorize reboot.\n' \
  "$snapshot_stamp"
