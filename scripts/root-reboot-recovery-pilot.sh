#!/usr/bin/env bash
set -euo pipefail

# Guard the live first-reboot recovery lifecycle around the already-tested,
# immutable Nix recovery bundle. This program deliberately has no reboot
# action. Arming and rebooting are separate operator authorizations.

repo_dir=/home/n0b0dy/Development/DGX-setup
repo_source=$repo_dir/scripts/root-reboot-recovery-pilot.sh
snapshot_source=$repo_dir/scripts/snapshot-root-reboot-recovery.sh
property_parser_source=$repo_dir/scripts/systemd-snapshot-property.sh
property_parser_test=$repo_dir/scripts/test-systemd-snapshot-property.sh
generation_one=/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager
generation_two=/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager
generation_three=/nix/store/w8kn2idc0ix6x1024qphv2fvmaf664d7-system-manager
recovery_bundle=/nix/store/wpikhcgj77ws90j4ivdp3498mlmffyax-dgx-root-reboot-recovery
recovery_bundle_drv=/nix/store/h4qaivg6jpf1fbgz8v8dmdi0j3xmgmps-dgx-root-reboot-recovery.drv
recovery_program=$recovery_bundle/bin/dgx-root-reboot-recovery
recovery_audit=/nix/store/skzn5n9f2ld8lji3ccvpfjmy6r0nk1bw-audit-root-canary-state.sh
recovery_transaction_sha256=b1f04f39169cc000b5a532545439693bafd9d6c62d0190e9aac2c231394a6be9
recovery_audit_sha256=19cac3ba416dc3705c9dc1a996afb82840e8f4bc2d657a78f969f3f42cfddb12
test_drv=/nix/store/jqmx45mxqqz34d4yjh3186xadb2ai6qx-container-test-dgx-root-canary-reboot-recovery-transaction.drv
test_output=/nix/store/p0ywhqdf58h5r83z1pah7arba4rqr0ka-container-test-dgx-root-canary-reboot-recovery-transaction
test_output_hash=sha256:0v7i51bmpjghm8v3cly7i82j3ysvk3in17s5av2465wy3zhzmgp8
nix_bin=/nix/var/nix/profiles/default/bin/nix
nix_store_bin=/nix/var/nix/profiles/default/bin/nix-store
state_path=/var/lib/system-manager/state/system-manager-state.json
recovery_state=/var/lib/dgx-setup/reboot-recovery/state
recovery_root=/nix/var/nix/gcroots/dgx-setup-root-canary-reboot-recovery-pilot
recovery_state_dir=/var/lib/dgx-setup/reboot-recovery
recovery_service_path=/etc/systemd/system/dgx-root-reboot-recovery.service
recovery_timer_path=/etc/systemd/system/dgx-root-reboot-recovery.timer
recovery_wants_path=/etc/systemd/system/timers.target.wants/dgx-root-reboot-recovery.timer
arm_phrase='ARM PERSISTENT RECOVERY'
disarm_phrase='DISARM PREBOOT RECOVERY'
confirm_phrase='KEEP REBOOTED GENERATION THREE'
cleanup_phrase='CLEAN ROLLED BACK REBOOT RECOVERY'
snapshot_age=UNKNOWN

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
  /etc/systemd/system/default.target.wants/system-manager.target
)

recovery_paths=(
  "$recovery_root"
  "$recovery_state_dir"
  "$recovery_service_path"
  "$recovery_timer_path"
  "$recovery_wants_path"
)

usage() {
  printf '%s\n' \
    "Usage: sudo $(basename "$0") arm /absolute/private/reboot-recovery-snapshot" \
    "       sudo $(basename "$0") disarm-preboot /absolute/private/reboot-recovery-snapshot" \
    "       sudo $(basename "$0") status /absolute/private/reboot-recovery-snapshot" \
    "       sudo $(basename "$0") confirm /absolute/private/reboot-recovery-snapshot" \
    "       sudo $(basename "$0") verify-rolled-back /absolute/private/reboot-recovery-snapshot" \
    "       sudo $(basename "$0") cleanup-rolled-back /absolute/private/reboot-recovery-snapshot" >&2
}

info() {
  printf 'INFO|%s|%s\n' "$1" "$2"
}

pass() {
  printf 'PASS|%s|%s\n' "$1" "$2"
}

die() {
  printf 'FAIL|%s\n' "$1" >&2
  exit 1
}

on_exit() {
  local status="$?" path state_status='' present=0

  ((status != 0)) || return 0
  if [[ -r "$recovery_state" ]]; then
    state_status="$(sed -n 's/^status=//p' "$recovery_state" 2>/dev/null || true)"
  fi
  for path in "${recovery_paths[@]}"; do
    path_exists "$path" && present=$((present + 1))
  done
  if [[ "$state_status" == armed && "$present" -eq "${#recovery_paths[@]}" ]]; then
    printf '%s\n' \
      'RECOVERY REMAINS ARMED; DO NOT REBOOT UNTIL THE FAILURE IS UNDERSTOOD.' >&2
    if [[ -n "${snapshot:-}" ]]; then
      printf '%s\n' \
        "Inspect: sudo $snapshot/root-reboot-recovery-pilot.sh status $snapshot" \
        "Same-boot cancellation: sudo $snapshot/root-reboot-recovery-pilot.sh disarm-preboot $snapshot" >&2
    fi
  elif ((present != 0)); then
    printf '%s\n' \
      'A PARTIAL OR NON-ARMED RECOVERY SURFACE REMAINS; DO NOT REBOOT OR DELETE IT MANUALLY.' \
      'Inspect the exact failure and reviewed recovery paths before taking another action.' >&2
  fi
}
trap on_exit EXIT

path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

require_commands() {
  local command_name

  for command_name in \
    awk bash cmp date find git grep hostname jq nvidia-smi readlink sed \
    sha256sum sort stat systemctl systemd-analyze tailscale timeout tr; do
    command -v "$command_name" >/dev/null 2>&1 ||
      die "required command is unavailable: $command_name"
  done
}

context_value() {
  local key="$1"

  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' \
    "$snapshot/context.txt"
}

snapshot_property() {
  local unit="$1"
  local property="$2"

  "$property_parser" "$snapshot/services.before.txt" "$unit" "$property"
}

current_boot_id() {
  local observed

  observed="$(tr -d '\n' </proc/sys/kernel/random/boot_id)"
  [[ "$observed" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] ||
    die 'kernel boot ID is malformed'
  printf '%s\n' "$observed"
}

assert_snapshot_fresh() {
  local timestamp snapshot_epoch now_epoch

  timestamp="$(context_value timestamp_utc)"
  snapshot_epoch="$(date -d "$timestamp" +%s 2>/dev/null || true)"
  now_epoch="$(date +%s)"
  [[ -n "$snapshot_epoch" ]] || die 'snapshot timestamp is missing or invalid'
  snapshot_age=$((now_epoch - snapshot_epoch))
  ((snapshot_age >= 0 && snapshot_age <= 1800)) ||
    die "snapshot is not in the current 30-minute recovery-arming window (age=${snapshot_age}s)"
}

assert_snapshot() {
  local self_sha snapshot_helper_sha pilot_sha parser_sha parser_test_sha
  local -a expected_files observed_files

  expected_files=(
    SHA256SUMS
    SNAPSHOT_COMPLETE
    context.txt
    managed-links.before.tsv
    manager-state.before.json
    protected-files.before.sha256
    recovery.before.tsv
    registration.before.tsv
    root-reboot-recovery-pilot.sh
    sanitized-health.before.txt
    services.before.txt
    snapshot-root-reboot-recovery.sh
    systemd-snapshot-property.sh
  )
  mapfile -t observed_files < <(
    find "$snapshot" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort
  )
  mapfile -t expected_files < <(printf '%s\n' "${expected_files[@]}" | sort)
  [[ "${observed_files[*]}" == "${expected_files[*]}" ]] ||
    die 'snapshot contains a missing or unexpected top-level file'
  [[ "$(<"$snapshot/SNAPSHOT_COMPLETE")" == 'Snapshot creation completed.' ]] ||
    die 'snapshot completion marker is invalid'
  [[ "$(stat -c %u:%g:%a "$snapshot")" == 0:0:700 ]] ||
    die 'snapshot must be root:root mode 0700'
  (
    cd "$snapshot"
    sha256sum -c SHA256SUMS >/dev/null
  ) || die 'snapshot checksum verification failed'

  for exact_record in \
    schema=1 \
    purpose=system-manager-first-reboot-recovery \
    host=sparkle-01 \
    repo_dir="$repo_dir" \
    generation_one="$generation_one" \
    generation_two="$generation_two" \
    generation_three="$generation_three" \
    recovery_bundle="$recovery_bundle" \
    recovery_bundle_drv="$recovery_bundle_drv" \
    recovery_transaction_sha256="$recovery_transaction_sha256" \
    recovery_audit="$recovery_audit" \
    recovery_audit_sha256="$recovery_audit_sha256" \
    test_drv="$test_drv" \
    test_output="$test_output" \
    test_output_hash="$test_output_hash" \
    nix_version=2.35.2 \
    manual_console_gate=required-before-arming \
    reboot_authorization=separate-and-not-granted-by-snapshot; do
    grep -Fx "$exact_record" "$snapshot/context.txt" >/dev/null ||
      die "snapshot context is missing exact record: $exact_record"
  done

  snapshot_helper_sha="$(context_value snapshot_program_sha256)"
  pilot_sha="$(context_value pilot_program_sha256)"
  parser_sha="$(context_value property_parser_sha256)"
  parser_test_sha="$(context_value property_parser_test_sha256)"
  [[ -n "$snapshot_helper_sha" &&
    "$snapshot_helper_sha" == "$(sha256sum "$snapshot/snapshot-root-reboot-recovery.sh" | awk '{print $1}')" ]] ||
    die 'snapshotted snapshot helper differs from its recorded checksum'
  [[ -n "$pilot_sha" &&
    "$pilot_sha" == "$(sha256sum "$snapshot/root-reboot-recovery-pilot.sh" | awk '{print $1}')" ]] ||
    die 'snapshotted recovery pilot differs from its recorded checksum'
  self_sha="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
  [[ "$self_sha" == "$pilot_sha" ]] ||
    die 'running recovery pilot differs from the snapshot-bound program'
  [[ -n "$parser_sha" &&
    "$parser_sha" == "$(sha256sum "$snapshot/systemd-snapshot-property.sh" | awk '{print $1}')" ]] ||
    die 'snapshotted systemd parser differs from its recorded checksum'
  [[ "$parser_test_sha" =~ ^[0-9a-f]{64}$ ]] ||
    die 'snapshot parser-test checksum is malformed'

  property_parser=$snapshot/systemd-snapshot-property.sh
  for program in \
    "$snapshot/snapshot-root-reboot-recovery.sh" \
    "$snapshot/root-reboot-recovery-pilot.sh" "$property_parser"; do
    [[ "$(stat -c %u:%g:%a "$program")" == 0:0:700 ]] ||
      die "snapshot program must be root:root mode 0700: $program"
    bash -n "$program" || die "snapshot program failed syntax validation: $program"
  done

  for store_path in \
    "$generation_one" "$generation_two" "$generation_three" \
    "$recovery_bundle" "$recovery_bundle_drv" \
    "$recovery_audit" "$test_drv" "$test_output"; do
    "$nix_store_bin" --check-validity "$store_path" >/dev/null 2>&1 ||
      die "snapshot-bound store path is invalid: $store_path"
  done
  [[ "$($nix_store_bin --query --deriver "$recovery_bundle")" == "$recovery_bundle_drv" ]] ||
    die 'production recovery bundle has an unexpected deriver'
  [[ "$($nix_store_bin --query --deriver "$test_output")" == "$test_drv" ]] ||
    die 'recovery test output has an unexpected deriver'
  [[ "$($nix_store_bin --query --hash "$test_output")" == "$test_output_hash" ]] ||
    die 'recovery test output hash differs from passed evidence'
  [[ "$(sha256sum "$recovery_audit" | awk '{print $1}')" == "$recovery_audit_sha256" ]] ||
    die 'snapshot-bound postboot auditor differs from its reviewed checksum'
  systemd-analyze verify \
    "$recovery_bundle/lib/systemd/system/dgx-root-reboot-recovery.service" \
    "$recovery_bundle/lib/systemd/system/dgx-root-reboot-recovery.timer" ||
    die 'production recovery unit validation failed'

  snapshot_boot_id="$(context_value arming_boot_id)"
  [[ "$snapshot_boot_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] ||
    die 'snapshot arming boot ID is malformed'
  snapshot_policy_drv="$(context_value root_policy_drv)"
  "$nix_store_bin" --check-validity "$snapshot_policy_drv" >/dev/null 2>&1 ||
    die 'snapshot root-manager policy derivation is invalid'
  pass snapshot "$snapshot is complete, private, checksum-valid, and bound to the exact recovery evidence"
}

assert_repo_arm_evidence() {
  local current_commit current_status current_policy_drv manifest_json
  local current_generation_one current_generation_two current_generation_three
  local current_bundle current_test_drv current_test_output
  local snapshot_sha pilot_sha parser_sha parser_test_sha

  [[ "$(readlink -f -- "${BASH_SOURCE[0]}")" == "$repo_source" ]] ||
    die 'run arm from the exact repository pilot, not the snapshotted postboot copy'
  current_commit="$(git -C "$repo_dir" rev-parse HEAD)"
  current_status="$(git -C "$repo_dir" status --porcelain --untracked-files=all)"
  [[ "$current_commit" == "$(context_value repo_commit)" ]] ||
    die 'repository commit changed after the snapshot'
  [[ -z "$current_status" ]] ||
    die 'repository must remain clean for recovery arming'
  assert_snapshot_fresh

  current_generation_one="$($nix_bin --extra-experimental-features 'nix-command flakes' eval --raw --no-write-lock-file .#packages.aarch64-linux.root-system-canary.outPath)"
  current_generation_two="$($nix_bin --extra-experimental-features 'nix-command flakes' eval --raw --no-write-lock-file .#packages.aarch64-linux.root-system-canary-generation-two.outPath)"
  current_generation_three="$($nix_bin --extra-experimental-features 'nix-command flakes' eval --raw --no-write-lock-file .#packages.aarch64-linux.root-system-canary-generation-three-boot.outPath)"
  current_bundle="$($nix_bin --extra-experimental-features 'nix-command flakes' eval --raw --no-write-lock-file .#packages.aarch64-linux.root-reboot-recovery.outPath)"
  current_test_drv="$($nix_bin --extra-experimental-features 'nix-command flakes' eval --raw --no-write-lock-file .#checks.aarch64-linux.root-canary-reboot-recovery-transaction-container.drvPath)"
  current_test_output="$($nix_bin --extra-experimental-features 'nix-command flakes' eval --raw --no-write-lock-file .#checks.aarch64-linux.root-canary-reboot-recovery-transaction-container.outPath)"
  current_policy_drv="$($nix_bin --extra-experimental-features 'nix-command flakes' eval --raw --no-write-lock-file .#checks.aarch64-linux.root-manager-policy.drvPath)"
  [[ "$current_generation_one" == "$generation_one" &&
    "$current_generation_two" == "$generation_two" &&
    "$current_generation_three" == "$generation_three" &&
    "$current_bundle" == "$recovery_bundle" &&
    "$current_test_drv" == "$test_drv" && "$current_test_output" == "$test_output" ]] ||
    die 'current flake no longer matches the snapshot-bound candidates/recovery proof'
  [[ "$current_policy_drv" == "$snapshot_policy_drv" ]] ||
    die 'root-manager policy derivation changed after the snapshot'

  snapshot_sha="$(sha256sum "$snapshot_source" | awk '{print $1}')"
  pilot_sha="$(sha256sum "$repo_source" | awk '{print $1}')"
  parser_sha="$(sha256sum "$property_parser_source" | awk '{print $1}')"
  parser_test_sha="$(sha256sum "$property_parser_test" | awk '{print $1}')"
  [[ "$snapshot_sha" == "$(context_value snapshot_program_sha256)" &&
    "$pilot_sha" == "$(context_value pilot_program_sha256)" &&
    "$parser_sha" == "$(context_value property_parser_sha256)" &&
    "$parser_test_sha" == "$(context_value property_parser_test_sha256)" ]] ||
    die 'repository helper changed after the snapshot'
  "$property_parser_test" >/dev/null ||
    die 'systemd snapshot-property regression test failed'

  manifest_json="$($nix_bin --extra-experimental-features 'nix-command flakes' eval --json --no-write-lock-file .#lib.dgxRootManagerManifest.aarch64-linux)"
  jq -e \
    --arg snapshot_sha "$snapshot_sha" --arg pilot_sha "$pilot_sha" \
    --arg parser_sha "$parser_sha" --arg parser_test_sha "$parser_test_sha" '
      .bootPersistence.status == "live-generation-three-boot-linked-retained" and
      .bootPersistence.rebootRecovery.status ==
        "live-recovery-designed-host-not-armed" and
      .bootPersistence.rebootRecovery.isolatedTransactionTest.result == "passed" and
      .bootPersistence.rebootRecovery.isolatedTransactionTest.matchesCurrent == true and
      .bootPersistence.rebootRecovery.livePilot.status ==
        "repository-design-complete-host-not-armed" and
      .bootPersistence.rebootRecovery.livePilot.snapshotProgram.sha256 ==
        $snapshot_sha and
      .bootPersistence.rebootRecovery.livePilot.pilotProgram.sha256 ==
        $pilot_sha and
      .bootPersistence.rebootRecovery.livePilot.systemdSnapshotPropertyProgram.sha256 ==
        $parser_sha and
      .bootPersistence.rebootRecovery.livePilot.systemdSnapshotPropertyTest.sha256 ==
        $parser_test_sha and
      .bootPersistence.rebootRecovery.livePilot.hostRecoveryArmed == false and
      .bootPersistence.rebootRecovery.livePilot.hostRebootPerformed == false
    ' >/dev/null <<<"$manifest_json" ||
    die 'current manifest no longer matches the exact unarmed recovery design'
  pass repository 'clean commit, helper hashes, manifest, policy, and passed recovery test remain exact'
}

assert_managed_links_match_snapshot() {
  local index=0 kind path expected extra

  while IFS='|' read -r kind path expected extra; do
    [[ "$index" -lt "${#managed_paths[@]}" ]] ||
      die 'snapshot managed-link inventory has unexpected extra records'
    [[ "$kind" == EXACT_SYMLINK && -z "$extra" ]] ||
      die 'snapshot managed-link record is malformed'
    [[ "$path" == "${managed_paths[$index]}" ]] ||
      die 'snapshot managed-link order/path differs from the reviewed surface'
    [[ -L "$path" && "$(readlink -f -- "$path" 2>/dev/null || true)" == "$expected" ]] ||
      die "live managed link differs from the snapshot: $path"
    index=$((index + 1))
  done <"$snapshot/managed-links.before.tsv"
  [[ "$index" -eq "${#managed_paths[@]}" ]] ||
    die 'snapshot managed-link inventory is incomplete'
}

assert_protected_units() {
  local mode="$1" unit before_load current_load before_active current_active
  local before_fragment current_fragment before_reload current_reload
  local before_substate current_substate before_pid current_pid
  local before_started current_started

  for unit in "${protected_units[@]}"; do
    before_load="$(snapshot_property "$unit" LoadState)"
    current_load="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
    before_active="$(snapshot_property "$unit" ActiveState)"
    current_active="$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)"
    before_fragment="$(snapshot_property "$unit" FragmentPath)"
    current_fragment="$(systemctl show "$unit" -p FragmentPath --value 2>/dev/null || true)"
    before_reload="$(snapshot_property "$unit" NeedDaemonReload)"
    current_reload="$(systemctl show "$unit" -p NeedDaemonReload --value 2>/dev/null || true)"
    current_pid="$(systemctl show "$unit" -p MainPID --value 2>/dev/null || true)"
    current_started="$(systemctl show "$unit" -p ActiveEnterTimestampMonotonic --value 2>/dev/null || true)"
    [[ "$before_load" == loaded && "$current_load" == loaded &&
      "$before_active" == active && "$current_active" == active ]] ||
      die "$unit is not loaded and active as required"
    [[ -n "$before_fragment" && "$current_fragment" == "$before_fragment" ]] ||
      die "$unit changed FragmentPath"
    [[ "$before_reload" == no && "$current_reload" == no ]] ||
      die "$unit has a pending daemon reload"
    [[ "$current_pid" =~ ^[1-9][0-9]*$ && "$current_started" =~ ^[1-9][0-9]*$ ]] ||
      die "$unit lacks a live process/start timestamp"
    if [[ "$mode" == same-boot ]]; then
      before_substate="$(snapshot_property "$unit" SubState)"
      current_substate="$(systemctl show "$unit" -p SubState --value 2>/dev/null || true)"
      before_pid="$(snapshot_property "$unit" MainPID)"
      before_started="$(snapshot_property "$unit" ActiveEnterTimestampMonotonic)"
      [[ -n "$before_substate" && "$current_substate" == "$before_substate" ]] ||
        die "$unit changed SubState before arming"
      [[ "$current_pid" == "$before_pid" ]] || die "$unit changed MainPID before arming"
      [[ "$current_started" == "$before_started" ]] ||
        die "$unit changed active-enter timestamp before arming"
    fi
  done
  pass protected_units "all seven factory/access services satisfy $mode continuity"
}

assert_health() {
  local system_state failed_units gpu_state status_json prefs_json
  local backend online want_running run_ssh

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
    die "Tailscale health failed: backend=$backend;online=$online;WantRunning=$want_running;RunSSH=$run_ssh"
  pass health "systemd=running;failed_units=0;gpu=$gpu_state;tailscale=$backend/$online;RunSSH=$run_ssh"
}

assert_protected_files() {
  sha256sum -c "$snapshot/protected-files.before.sha256" >/dev/null ||
    die 'a protected Nix/account file changed from the snapshot'
}

assert_recovery_absent() {
  local path unit load_state

  for path in "${recovery_paths[@]}"; do
    path_exists "$path" && die "unexpected recovery path exists: $path"
  done
  for unit in dgx-root-reboot-recovery.service dgx-root-reboot-recovery.timer; do
    load_state="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
    [[ -z "$load_state" || "$load_state" == not-found ]] ||
      die "unexpected recovery unit remains loaded: $unit ($load_state)"
  done
}

assert_prearm_state() {
  local state_class

  [[ "$(current_boot_id)" == "$snapshot_boot_id" ]] ||
    die 'host boot ID changed after the snapshot; create a new snapshot'
  state_class="$(
    "$repo_dir/scripts/audit-root-canary-state.sh" \
      "$generation_three" registered-third-boot \
      "$generation_one" "$generation_two" 2>/dev/null || true
  )"
  [[ "$state_class" == ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED ]] ||
    die "expected exact pre-reboot generation three; observed ${state_class:-UNKNOWN}"
  cmp -s "$state_path" "$snapshot/manager-state.before.json" ||
    die 'live manager state changed after the snapshot'
  assert_managed_links_match_snapshot
  assert_recovery_absent
  assert_protected_files
  assert_protected_units same-boot
  assert_health
  pass prearm 'exact generation three and all protected host state remain unchanged'
}

assert_new_boot() {
  [[ "$(current_boot_id)" != "$snapshot_boot_id" ]] ||
    die 'postboot action refuses the original arming boot'
}

assert_postboot_common() {
  assert_new_boot
  assert_protected_files
  assert_protected_units postboot
  assert_health
}

audit_postboot_generation_three() {
  local observed

  observed="$(
    bash "$recovery_audit" \
      "$generation_three" registered-third-boot \
      "$generation_one" "$generation_two" postboot absent 2>/dev/null || true
  )"
  [[ "$observed" == ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_REBOOTED_RETAINED ]] ||
    die "postboot generation-three audit returned ${observed:-UNKNOWN}"
}

audit_preboot_generation_three() {
  local observed

  observed="$(
    bash "$recovery_audit" \
      "$generation_three" registered-third-boot \
      "$generation_one" "$generation_two" activation absent 2>/dev/null || true
  )"
  [[ "$observed" == ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED ]] ||
    die "preboot generation-three audit returned ${observed:-UNKNOWN}"
}

audit_rolled_back_generation_two() {
  local recovery_expectation="${1:-verified-by-caller}" observed

  observed="$(
    bash "$recovery_audit" \
      "$generation_two" registered-second-triple-retained \
      "$generation_one" "$generation_three" \
      activation "$recovery_expectation" 2>/dev/null || true
  )"
  [[ "$observed" == ACTIVE_REGISTERED_GENERATION_TWO_TRIPLE_RETAINED ]] ||
    die "rolled-back generation-two audit returned ${observed:-UNKNOWN}"
}

arm_recovery() {
  local reply arming_id

  assert_repo_arm_evidence
  assert_prearm_state
  assert_snapshot_fresh
  printf '\n%s\n' \
    'Automatic arming preflight passed. Independently verify the physical keyboard/display/local terminal.' \
    "Type exactly $arm_phrase to install persistent recovery for a separately authorized reboot." \
    'This command will not reboot the host.'
  printf '> '
  read -r -t 300 reply || die 'recovery-arming confirmation timed out'
  [[ "$reply" == "$arm_phrase" ]] || die 'recovery-arming confirmation did not match'

  "$recovery_program" arm
  "$recovery_program" verify-armed-preboot
  arming_id="$(sed -n 's/^arming_boot_id=//p' "$recovery_state")"
  [[ "$arming_id" == "$snapshot_boot_id" ]] ||
    die 'armed recovery state does not bind the snapshotted boot ID'
  assert_protected_files
  assert_protected_units same-boot
  assert_health
  pass arming 'persistent first-reboot recovery is exact, enabled, and inactive on this boot'
  printf '%s\n' \
    'ARMED: the next boot has a ten-minute automatic generation-two rollback.' \
    'NOT REBOOTED: this command did not reboot and grants no reboot authority.' \
    "POSTBOOT RETAIN: sudo $snapshot/root-reboot-recovery-pilot.sh confirm $snapshot" \
    "POSTBOOT STATUS: sudo $snapshot/root-reboot-recovery-pilot.sh status $snapshot"
}

disarm_preboot_recovery() {
  local reply

  [[ "$(current_boot_id)" == "$snapshot_boot_id" ]] ||
    die 'preboot disarm refuses a changed kernel boot ID'
  "$recovery_program" verify-armed-preboot
  assert_protected_files
  assert_protected_units same-boot
  assert_health
  printf '\n%s\n' \
    'Exact recovery is armed on the original pre-reboot boot.' \
    "Type exactly $disarm_phrase to cancel this reboot window without changing generation three."
  printf '> '
  read -r -t 300 reply || die 'preboot disarm confirmation timed out'
  [[ "$reply" == "$disarm_phrase" ]] ||
    die 'preboot disarm confirmation did not match'
  "$recovery_program" disarm-preboot
  assert_recovery_absent
  audit_preboot_generation_three
  assert_protected_files
  assert_protected_units same-boot
  assert_health
  pass disarm 'persistent recovery removed on the original boot; generation three remains exact'
}

status_recovery() {
  local current status observed

  current="$(current_boot_id)"
  if [[ -r "$recovery_state" ]]; then
    status="$(sed -n 's/^status=//p' "$recovery_state")"
    case "$status" in
      armed)
        if [[ "$current" == "$snapshot_boot_id" ]]; then
          assert_protected_files
          assert_protected_units same-boot
          assert_health
          "$recovery_program" verify-armed-preboot
          pass status 'recovery is armed/inactive on the original boot; no reboot has occurred'
        else
          assert_postboot_common
          "$recovery_program" verify-armed-postboot
          pass status 'generation three booted; rollback timer is active/waiting for confirmation'
        fi
        ;;
      rolled-back)
        assert_postboot_common
        "$recovery_program" verify-rolled-back
        audit_rolled_back_generation_two
        pass status 'automatic rollback restored generation two; exact evidence awaits cleanup authorization'
        ;;
      *)
        die "unknown recovery state status: ${status:-EMPTY}"
        ;;
    esac
  else
    assert_recovery_absent
    if [[ "$current" == "$snapshot_boot_id" ]]; then
      assert_protected_files
      assert_protected_units same-boot
      assert_health
      audit_preboot_generation_three
      observed=ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED
    else
      assert_postboot_common
      audit_postboot_generation_three
      observed=ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_REBOOTED_RETAINED
    fi
    pass status "$observed; recovery surface is absent"
  fi
}

confirm_recovery() {
  local reply

  assert_postboot_common
  "$recovery_program" verify-armed-postboot
  printf '\n%s\n' \
    'Postboot recovery and protected-host checks passed.' \
    'Verify the physical console one more time.' \
    "Type exactly $confirm_phrase to retain generation three and remove recovery."
  printf '> '
  read -r -t 300 reply || die 'postboot confirmation timed out; rollback remains armed'
  [[ "$reply" == "$confirm_phrase" ]] ||
    die 'postboot confirmation did not match; rollback remains armed'
  "$recovery_program" confirm "$confirm_phrase"
  assert_recovery_absent
  audit_postboot_generation_three
  assert_protected_files
  assert_protected_units postboot
  assert_health
  pass confirmation 'rebooted generation three retained and exact persistent recovery removed'
}

verify_rolled_back() {
  assert_postboot_common
  "$recovery_program" verify-rolled-back
  audit_rolled_back_generation_two
  pass rollback 'exact registered/live no-boot generation two is restored; recovery evidence remains'
}

cleanup_rolled_back() {
  local reply

  verify_rolled_back
  printf '\n%s\n' \
    'Exact automatic rollback is verified.' \
    "Type exactly $cleanup_phrase to remove only the temporary recovery evidence."
  printf '> '
  read -r -t 300 reply || die 'rolled-back cleanup confirmation timed out'
  [[ "$reply" == "$cleanup_phrase" ]] ||
    die 'rolled-back cleanup confirmation did not match'
  "$recovery_program" cleanup-rolled-back "$cleanup_phrase"
  assert_recovery_absent
  audit_rolled_back_generation_two absent
  assert_protected_files
  assert_protected_units postboot
  assert_health
  pass cleanup 'verified rollback evidence removed; all three generation roots remain retained'
}

if [[ "$EUID" -ne 0 ]]; then
  die 'run this recovery pilot as root'
fi
if [[ "$#" -ne 2 ]]; then
  usage
  exit 2
fi

action="$1"
case "$action" in
  arm | disarm-preboot | status | confirm | verify-rolled-back | cleanup-rolled-back)
    ;;
  *)
    usage
    exit 2
    ;;
esac

PATH=/nix/var/nix/profiles/default/bin:/usr/sbin:/usr/bin:/sbin:/bin
NIX_USER_CONF_FILES=/dev/null
export PATH NIX_USER_CONF_FILES
require_commands
[[ "$(hostname)" == sparkle-01 ]] || die 'this recovery pilot is scoped to sparkle-01'
[[ -x "$nix_bin" && -x "$nix_store_bin" ]] ||
  die 'reviewed root-profile Nix tools are unavailable'
[[ "$($nix_bin --version)" == 'nix (Nix) 2.35.2' ]] ||
  die 'active root-profile Nix is not exact reviewed 2.35.2'
cd "$repo_dir"

snapshot="$(readlink -f -- "$2")"
case "$snapshot" in
  "$repo_dir"/inventory/sparkle-01/raw/system-manager-reboot-recovery/*)
    ;;
  *)
    die "snapshot must be below $repo_dir/inventory/sparkle-01/raw/system-manager-reboot-recovery"
    ;;
esac
[[ -t 0 && -t 1 ]] || die 'run the recovery pilot from an interactive terminal'

printf '# DGX System Manager first-reboot recovery pilot\n'
printf '# timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
info action "$action"
info generation_three "$generation_three"
info recovery_bundle "$recovery_bundle"
info snapshot "$snapshot"
info reboot 'never performed by this program'

assert_snapshot

case "$action" in
  arm)
    arm_recovery
    ;;
  disarm-preboot)
    disarm_preboot_recovery
    ;;
  status)
    status_recovery
    ;;
  confirm)
    confirm_recovery
    ;;
  verify-rolled-back)
    verify_rolled_back
    ;;
  cleanup-rolled-back)
    cleanup_rolled_back
    ;;
esac
