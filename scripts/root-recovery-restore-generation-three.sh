#!/usr/bin/env bash
set -euo pipefail

# Restore the exact generation-three boot-linked state after a verified
# persistent-recovery rollback. This performs no reboot and never removes any
# of the three direct pilot roots. A transient timer restores generation two
# unless verified postflight completes and this helper disarms it. If the
# terminal disappears after activation, rerunning the helper resumes the exact
# in-flight transaction instead of requiring a second typed confirmation.

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
self_source=$repo_dir/scripts/root-recovery-restore-generation-three.sh
transaction_source=$repo_dir/scripts/root-boot-persistence-transaction.sh
property_parser_source=$repo_dir/scripts/systemd-snapshot-property.sh
generation_one=/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager
generation_two=/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager
generation_three=/nix/store/w8kn2idc0ix6x1024qphv2fvmaf664d7-system-manager
transaction_sha256=53eb8c4d03a4c24764f519e358f3c5c813e66f189efc07e50f82cd19841d8288
boot_test_drv=/nix/store/i5skjqyw16qgbvb4azr68msrqfz64d7k-container-test-dgx-root-canary-boot-persistence-transaction.drv
boot_test_output=/nix/store/d3ymf91l07rvai5pzz9ygj3vl3g9xss3-container-test-dgx-root-canary-boot-persistence-transaction
boot_test_hash=sha256:0lxm3pjsd4yy9zl49zx6cbydc9iid1i7mdrajkinkfzszg5k7ikn
nix_bin=/nix/var/nix/profiles/default/bin/nix
nix_store_bin=/nix/var/nix/profiles/default/bin/nix-store
state_path=/var/lib/system-manager/state/system-manager-state.json
generation_one_root=/nix/var/nix/gcroots/dgx-setup-root-canary-pilot
generation_two_root=/nix/var/nix/gcroots/dgx-setup-root-canary-generation-two-pilot
generation_three_root=/nix/var/nix/gcroots/dgx-setup-root-canary-boot-persistence-pilot
recovery_root=/nix/var/nix/gcroots/dgx-setup-root-canary-reboot-recovery-pilot
recovery_state_dir=/var/lib/dgx-setup/reboot-recovery
recovery_service_path=/etc/systemd/system/dgx-root-reboot-recovery.service
recovery_timer_path=/etc/systemd/system/dgx-root-reboot-recovery.timer
recovery_wants_path=/etc/systemd/system/timers.target.wants/dgx-root-reboot-recovery.timer
rollback_unit=dgx-root-recovery-restore-rollback
snapshot_root=$repo_dir/inventory/sparkle-01/raw/system-manager-recovery-restore
transaction=$transaction_source
property_parser=$property_parser_source
timer_armed=false
mutation_started=false

protected_units=(
  nix-daemon.service
  tailscaled.service
  gdm.service
  docker.service
  dgx-dashboard.service
  dgx-dashboard-admin.service
  nvidia-persistenced.service
)

recovery_paths=(
  "$recovery_root"
  "$recovery_state_dir"
  "$recovery_service_path"
  "$recovery_timer_path"
  "$recovery_wants_path"
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
  "$rollback_unit.timer"
  "$rollback_unit.service"
)

pass() {
  printf 'PASS|%s|%s\n' "$1" "$2"
}

info() {
  printf 'INFO|%s|%s\n' "$1" "$2"
}

die() {
  printf 'FAIL|%s\n' "$1" >&2
  exit 1
}

path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

on_exit() {
  local status="$?"

  ((status != 0)) || return 0
  if [[ "$timer_armed" == true ]]; then
    printf '%s\n' \
      "ROLLBACK ARMED: $rollback_unit.timer will restore exact generation two; do not reboot or remove any pilot root." >&2
  elif [[ "$mutation_started" == true ]]; then
    printf '%s\n' \
      'MUTATION STARTED WITHOUT A CONFIRMED TIMER STATE; inspect the exact transaction before acting.' >&2
  fi
}
trap on_exit EXIT

require_commands() {
  local command_name

  for command_name in \
    awk bash cmp date find git grep hostname install jq loginctl nvidia-smi \
    readlink sed sha256sum sleep sort stat systemctl systemd-run tailscale \
    timeout tr uname; do
    command -v "$command_name" >/dev/null 2>&1 ||
      die "required command is unavailable: $command_name"
  done
}

assert_nix_runtime_ready() {
  local service_active service_substate service_pid service_started
  local service_result socket_load socket_active socket_substate socket_reload
  local socket_result socket_fragment

  service_active="$(systemctl show nix-daemon.service -p ActiveState --value 2>/dev/null || true)"
  service_substate="$(systemctl show nix-daemon.service -p SubState --value 2>/dev/null || true)"
  service_pid="$(systemctl show nix-daemon.service -p MainPID --value 2>/dev/null || true)"
  service_started="$(systemctl show nix-daemon.service -p ActiveEnterTimestampMonotonic --value 2>/dev/null || true)"
  service_result="$(systemctl show nix-daemon.service -p Result --value 2>/dev/null || true)"
  case "$service_active" in
    active)
      [[ "$service_pid" =~ ^[1-9][0-9]*$ &&
        "$service_started" =~ ^[1-9][0-9]*$ && "$service_result" == success ]] ||
        die 'active nix-daemon.service lacks a healthy process/start result'
      ;;
    inactive)
      [[ "$service_substate" == dead && "$service_pid" == 0 &&
        "$service_result" == success ]] ||
        die 'inactive nix-daemon.service is not cleanly idle'
      ;;
    *)
      die "nix-daemon.service is neither active nor cleanly idle ($service_active/$service_substate)"
      ;;
  esac

  socket_load="$(systemctl show nix-daemon.socket -p LoadState --value 2>/dev/null || true)"
  socket_active="$(systemctl show nix-daemon.socket -p ActiveState --value 2>/dev/null || true)"
  socket_substate="$(systemctl show nix-daemon.socket -p SubState --value 2>/dev/null || true)"
  socket_reload="$(systemctl show nix-daemon.socket -p NeedDaemonReload --value 2>/dev/null || true)"
  socket_result="$(systemctl show nix-daemon.socket -p Result --value 2>/dev/null || true)"
  socket_fragment="$(systemctl show nix-daemon.socket -p FragmentPath --value 2>/dev/null || true)"
  [[ "$socket_load" == loaded && "$socket_active" == active &&
    ("$socket_substate" == listening || "$socket_substate" == running) &&
    "$socket_reload" == no && "$socket_result" == success &&
    -n "$socket_fragment" ]] ||
    die 'nix-daemon.socket is not loaded/active/socket-ready/reload-clean'
}

assert_protected_units() {
  local baseline="$1" unit before_load current_load before_active current_active
  local before_fragment current_fragment before_reload current_reload
  local before_substate current_substate before_pid current_pid
  local before_started current_started before_result current_result

  before_load="$($property_parser "$baseline" nix-daemon.socket LoadState)"
  current_load="$(systemctl show nix-daemon.socket -p LoadState --value 2>/dev/null || true)"
  before_active="$($property_parser "$baseline" nix-daemon.socket ActiveState)"
  current_active="$(systemctl show nix-daemon.socket -p ActiveState --value 2>/dev/null || true)"
  before_substate="$($property_parser "$baseline" nix-daemon.socket SubState)"
  current_substate="$(systemctl show nix-daemon.socket -p SubState --value 2>/dev/null || true)"
  before_fragment="$($property_parser "$baseline" nix-daemon.socket FragmentPath)"
  current_fragment="$(systemctl show nix-daemon.socket -p FragmentPath --value 2>/dev/null || true)"
  before_reload="$($property_parser "$baseline" nix-daemon.socket NeedDaemonReload)"
  current_reload="$(systemctl show nix-daemon.socket -p NeedDaemonReload --value 2>/dev/null || true)"
  before_result="$($property_parser "$baseline" nix-daemon.socket Result)"
  current_result="$(systemctl show nix-daemon.socket -p Result --value 2>/dev/null || true)"
  [[ "$before_load" == loaded && "$current_load" == loaded &&
    "$before_active" == active && "$current_active" == active &&
    ("$before_substate" == listening || "$before_substate" == running) &&
    ("$current_substate" == listening || "$current_substate" == running) &&
    "$before_result" == success && "$current_result" == success ]] ||
    die 'nix-daemon.socket is not continuously healthy from the snapshot'
  [[ -n "$before_fragment" && "$current_fragment" == "$before_fragment" ]] ||
    die 'nix-daemon.socket changed FragmentPath'
  [[ "$before_reload" == no && "$current_reload" == no ]] ||
    die 'nix-daemon.socket has a pending daemon reload'

  assert_nix_runtime_ready
  for unit in "${protected_units[@]}"; do
    before_load="$($property_parser "$baseline" "$unit" LoadState)"
    current_load="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
    before_active="$($property_parser "$baseline" "$unit" ActiveState)"
    current_active="$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)"
    before_fragment="$($property_parser "$baseline" "$unit" FragmentPath)"
    current_fragment="$(systemctl show "$unit" -p FragmentPath --value 2>/dev/null || true)"
    before_reload="$($property_parser "$baseline" "$unit" NeedDaemonReload)"
    current_reload="$(systemctl show "$unit" -p NeedDaemonReload --value 2>/dev/null || true)"
    before_substate="$($property_parser "$baseline" "$unit" SubState)"
    current_substate="$(systemctl show "$unit" -p SubState --value 2>/dev/null || true)"
    before_pid="$($property_parser "$baseline" "$unit" MainPID)"
    current_pid="$(systemctl show "$unit" -p MainPID --value 2>/dev/null || true)"
    before_started="$($property_parser "$baseline" "$unit" ActiveEnterTimestampMonotonic)"
    current_started="$(systemctl show "$unit" -p ActiveEnterTimestampMonotonic --value 2>/dev/null || true)"
    before_result="$($property_parser "$baseline" "$unit" Result)"
    current_result="$(systemctl show "$unit" -p Result --value 2>/dev/null || true)"
    [[ "$before_load" == loaded && "$current_load" == loaded ]] ||
      die "$unit is not loaded exactly as snapshotted"
    [[ -n "$before_fragment" && "$current_fragment" == "$before_fragment" ]] ||
      die "$unit changed FragmentPath"
    [[ "$before_reload" == no && "$current_reload" == no ]] ||
      die "$unit has a pending daemon reload"
    if [[ "$unit" == nix-daemon.service ]]; then
      case "$before_active" in
        active)
          [[ "$before_result" == success && "$current_active" == active &&
            "$current_result" == success && "$current_pid" == "$before_pid" &&
            "$current_started" == "$before_started" ]] ||
            die 'active nix-daemon.service changed after the snapshot'
          ;;
        inactive)
          [[ "$before_substate" == dead && "$before_pid" == 0 &&
            "$before_result" == success ]] ||
            die 'snapshotted nix-daemon.service was not cleanly idle'
          # A later repository Nix query may legitimately activate the daemon
          # through the unchanged socket. The runtime check above proves that
          # either resulting state is healthy; it is not treated as a restart.
          ;;
        *)
          die 'nix-daemon.service snapshot state was not healthy'
          ;;
      esac
      continue
    fi
    [[ "$before_active" == active && "$current_active" == active ]] ||
      die "$unit is not active exactly as snapshotted"
    [[ "$before_result" == success && "$current_result" == success &&
      "$current_pid" == "$before_pid" && "$current_started" == "$before_started" ]] ||
      die "$unit restarted after the snapshot"
  done
  pass protected_units 'six continuously running factory/access services are unrestarted; Nix is healthy through its exact socket-activated runtime'
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
  jq -e . >/dev/null 2>&1 <<<"$status_json" || die 'Tailscale status did not return valid JSON'
  jq -e . >/dev/null 2>&1 <<<"$prefs_json" || die 'Tailscale preferences did not return valid JSON'
  backend="$(jq -r '.BackendState // "UNKNOWN"' <<<"$status_json")"
  online="$(jq -r 'if .Self.Online == null then "UNKNOWN" else (.Self.Online | tostring) end' <<<"$status_json")"
  want_running="$(jq -r 'if .WantRunning == null then "UNKNOWN" else (.WantRunning | tostring) end' <<<"$prefs_json")"
  run_ssh="$(jq -r 'if .RunSSH == null then "UNKNOWN" else (.RunSSH | tostring) end' <<<"$prefs_json")"
  [[ "$backend" == Running && "$online" == true &&
    "$want_running" == true && "$run_ssh" == true ]] ||
    die 'sanitized Tailscale health gate failed'
  pass health "systemd=running;failed_units=0;gpu=$gpu_state;tailscale=$backend/$online;RunSSH=$run_ssh"
}

assert_recovery_absent() {
  local path unit load_state

  for path in "${recovery_paths[@]}"; do
    path_exists "$path" && die "recovery cleanup is incomplete: $path"
  done
  for unit in dgx-root-reboot-recovery.service dgx-root-reboot-recovery.timer; do
    load_state="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
    [[ -z "$load_state" || "$load_state" == not-found ]] ||
      die "recovery unit remains loaded: $unit ($load_state)"
  done
}

assert_generation_two() {
  local observed

  observed="$(
    "$repo_dir/scripts/audit-root-canary-state.sh" \
      "$generation_two" registered-second-triple-retained \
      "$generation_one" "$generation_three" 2>/dev/null || true
  )"
  [[ "$observed" == ACTIVE_REGISTERED_GENERATION_TWO_TRIPLE_RETAINED ]] ||
    die "expected exact recovery rollback state; observed ${observed:-UNKNOWN}"
}

assert_generation_three() {
  local observed

  "$transaction" verify-after \
    "$generation_one" "$generation_two" "$generation_three" >/dev/null ||
    die 'boot transaction rejected restored generation three'
  observed="$(
    "$repo_dir/scripts/audit-root-canary-state.sh" \
      "$generation_three" registered-third-boot \
      "$generation_one" "$generation_two" 2>/dev/null || true
  )"
  [[ "$observed" == ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED ]] ||
    die "restored generation-three audit returned ${observed:-UNKNOWN}"
  [[ -L "$generation_one_root" && "$(readlink -- "$generation_one_root")" == "$generation_one" ]] ||
    die 'generation-one pilot root changed'
  [[ -L "$generation_two_root" && "$(readlink -- "$generation_two_root")" == "$generation_two" ]] ||
    die 'generation-two pilot root changed'
  [[ -L "$generation_three_root" && "$(readlink -- "$generation_three_root")" == "$generation_three" ]] ||
    die 'generation-three pilot root changed'
}

classify_generation_state() {
  local observed

  observed="$(
    "$repo_dir/scripts/audit-root-canary-state.sh" \
      "$generation_two" registered-second-triple-retained \
      "$generation_one" "$generation_three" 2>/dev/null || true
  )"
  if [[ "$observed" == ACTIVE_REGISTERED_GENERATION_TWO_TRIPLE_RETAINED ]]; then
    printf '%s\n' "$observed"
    return 0
  fi

  observed="$(
    "$repo_dir/scripts/audit-root-canary-state.sh" \
      "$generation_three" registered-third-boot \
      "$generation_one" "$generation_two" 2>/dev/null || true
  )"
  if [[ "$observed" == ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED ]]; then
    printf '%s\n' "$observed"
    return 0
  fi

  printf 'DRIFT\n'
}

load_resume_snapshot() {
  local candidate context_timestamp snapshot_epoch now_epoch age

  snapshot=
  while IFS= read -r candidate; do
    snapshot=$candidate
  done < <(find "$snapshot_root" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort)
  [[ -n "$snapshot" ]] || die 'generation three is live, but no restoration snapshot exists'
  [[ "$(stat -c '%u:%a' "$snapshot")" == 0:700 ]] ||
    die 'latest restoration snapshot is not root-owned mode 0700'
  grep -Fx 'Snapshot creation completed.' "$snapshot/SNAPSHOT_COMPLETE" >/dev/null 2>&1 ||
    die 'latest restoration snapshot is incomplete'
  (
    cd "$snapshot"
    sha256sum -c SHA256SUMS >/dev/null
  ) || die 'latest restoration snapshot failed checksum validation'
  grep -Fx 'schema=1' "$snapshot/context.txt" >/dev/null ||
    die 'latest restoration snapshot has an unexpected schema'
  grep -Fx 'purpose=restore-generation-three-after-verified-recovery-rollback' \
    "$snapshot/context.txt" >/dev/null || die 'latest restoration snapshot has the wrong purpose'
  for expected in \
    'host=sparkle-01' \
    "repo_commit=$repo_commit" \
    "restore_program_sha256=$self_sha" \
    "transaction_sha256=$transaction_sha256" \
    "generation_one=$generation_one" \
    "generation_two=$generation_two" \
    "generation_three=$generation_three" \
    'prestate=ACTIVE_REGISTERED_GENERATION_TWO_TRIPLE_RETAINED'; do
    grep -Fx -- "$expected" "$snapshot/context.txt" >/dev/null ||
      die "latest restoration snapshot context mismatch: $expected"
  done
  context_timestamp="$(awk -F= '$1 == "timestamp_utc" { sub(/^[^=]*=/, ""); print; exit }' "$snapshot/context.txt")"
  [[ -n "$context_timestamp" ]] || die 'latest restoration snapshot lacks a timestamp'
  snapshot_epoch="$(date -u -d "$context_timestamp" +%s)" ||
    die 'latest restoration snapshot timestamp is invalid'
  now_epoch="$(date -u +%s)"
  age=$((now_epoch - snapshot_epoch))
  ((age >= 0 && age <= 1800)) ||
    die "latest restoration snapshot is outside the 30-minute resume window (age=${age}s)"

  transaction=$snapshot/root-boot-persistence-transaction.sh
  property_parser=$snapshot/systemd-snapshot-property.sh
  [[ -x "$transaction" && -x "$property_parser" ]] ||
    die 'latest restoration snapshot lacks its executable reviewed helpers'
  stamp=${snapshot##*/}
  pass snapshot "$snapshot is complete, checksum-valid, current, and bound to this in-flight restoration"
}

assert_resume_timer() {
  local exec_start expected_arg

  [[ "$(systemctl show "$rollback_unit.timer" -p ActiveState --value 2>/dev/null || true)" == active &&
    "$(systemctl show "$rollback_unit.timer" -p SubState --value 2>/dev/null || true)" == waiting ]] ||
    die 'generation three is live without the exact active/waiting restoration rollback timer'
  exec_start="$(systemctl show "$rollback_unit.service" -p ExecStart --value --no-pager 2>/dev/null || true)"
  for expected_arg in \
    "$transaction" rollback-boot \
    "$generation_one" "$generation_two" "$generation_three"; do
    grep -F -- "$expected_arg" <<<"$exec_start" >/dev/null ||
      die "restoration rollback service lacks exact argument: $expected_arg"
  done
  pass resume 'found the exact in-flight restoration and its generation-two rollback timer'
}

stop_restoration_timer() {
  local timer_state service_state current_state attempt

  systemctl stop "$rollback_unit.timer" >/dev/null 2>&1 || true
  for ((attempt = 0; attempt < 30; attempt++)); do
    service_state="$(systemctl show "$rollback_unit.service" -p ActiveState --value 2>/dev/null || true)"
    [[ "$service_state" != active && "$service_state" != activating ]] && break
    sleep 1
  done
  timer_state="$(systemctl show "$rollback_unit.timer" -p ActiveState --value 2>/dev/null || true)"
  service_state="$(systemctl show "$rollback_unit.service" -p ActiveState --value 2>/dev/null || true)"
  current_state="$(classify_generation_state)"

  if [[ "$current_state" == ACTIVE_REGISTERED_GENERATION_TWO_TRIPLE_RETAINED ]]; then
    timer_armed=false
    mutation_started=false
    die 'rollback completed before retention; exact generation two is safe, so rerun restore'
  fi
  [[ -z "$timer_state" || "$timer_state" == inactive ]] ||
    die "restoration rollback timer remains $timer_state"
  [[ -z "$service_state" || "$service_state" == inactive || "$service_state" == dead ]] ||
    die "restoration rollback service remains $service_state"
  [[ "$current_state" == ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED ]] ||
    die "unexpected state after stopping restoration rollback: $current_state"
  timer_armed=false
  pass rollback 'verified postflight passed and the transient generation-two rollback is disarmed'
}

if [[ "$EUID" -ne 0 ]]; then
  die 'run through ./scripts/dgx-recovery restore, not directly as an unprivileged user'
fi
[[ "$#" -eq 0 ]] || die 'restore accepts no arguments'

PATH=/nix/var/nix/profiles/default/bin:/usr/sbin:/usr/bin:/sbin:/bin
NIX_USER_CONF_FILES=/dev/null
export PATH NIX_USER_CONF_FILES
require_commands
cd "$repo_dir"
[[ -t 0 && -t 1 ]] || die 'run restoration from an interactive terminal'
[[ "$(hostname)" == sparkle-01 ]] || die 'this restoration is scoped to sparkle-01'
[[ "$($nix_bin --version)" == 'nix (Nix) 2.35.2' ]] ||
  die 'active root-profile Nix is not exact reviewed 2.35.2'
[[ "$(readlink -f -- "${BASH_SOURCE[0]}")" == "$self_source" ]] ||
  die 'run the exact repository restoration helper'

for program in "$self_source" "$transaction_source" "$property_parser_source"; do
  [[ -x "$program" ]] || die "required reviewed program is unavailable: $program"
  bash -n "$program" || die "program failed syntax validation: $program"
done
[[ "$(sha256sum "$transaction_source" | awk '{print $1}')" == "$transaction_sha256" ]] ||
  die 'boot transaction differs from its exact passed checksum'

repo_commit="$(git -C "$repo_dir" rev-parse HEAD)"
[[ -z "$(git -C "$repo_dir" status --porcelain --untracked-files=all)" ]] ||
  die 'repository must be clean before restoration'
self_sha="$(sha256sum "$self_source" | awk '{print $1}')"
policy_drv="$($nix_bin --extra-experimental-features 'nix-command flakes' eval --raw --no-write-lock-file .#checks.aarch64-linux.root-manager-policy.drvPath)"
manifest_json="$($nix_bin --extra-experimental-features 'nix-command flakes' eval --json --no-write-lock-file .#lib.dgxRootManagerManifest.aarch64-linux)"
jq -e --arg self_sha "$self_sha" '
  .bootPersistence.rebootRecovery.liveAttempt.status ==
    "automatic-rollback-verified-cleaned" and
  .bootPersistence.rebootRecovery.liveAttempt.currentHostState ==
    "ACTIVE_REGISTERED_GENERATION_TWO_TRIPLE_RETAINED" and
  .bootPersistence.rebootRecovery.liveAttempt.recoverySurface == "absent" and
  .bootPersistence.rebootRecovery.restoration.status ==
    "attempt-one-rolled-back-retry-ready" and
  .bootPersistence.rebootRecovery.restoration.program.sha256 == $self_sha and
  .bootPersistence.rebootRecovery.restoration.consoleAcknowledgement ==
    "press-enter-after-local-console-check" and
  .bootPersistence.rebootRecovery.restoration.exactPhraseRequired == false and
  .bootPersistence.rebootRecovery.restoration.automaticRetentionAfterPostflight == true and
  .bootPersistence.rebootRecovery.restoration.resumableWhileRollbackTimerActive == true and
  .bootPersistence.rebootRecovery.restoration.performsReboot == false
' >/dev/null <<<"$manifest_json" ||
  die 'root-manager manifest does not match the verified rollback/restoration gate'

for store_path in \
  "$generation_one" "$generation_two" "$generation_three" \
  "$boot_test_drv" "$boot_test_output" "$policy_drv"; do
  "$nix_store_bin" --check-validity "$store_path" >/dev/null 2>&1 ||
    die "required exact store path is invalid: $store_path"
done
[[ "$($nix_store_bin --query --deriver "$boot_test_output")" == "$boot_test_drv" ]] ||
  die 'boot-persistence test output has an unexpected deriver'
[[ "$($nix_store_bin --query --hash "$boot_test_output")" == "$boot_test_hash" ]] ||
  die 'boot-persistence test output hash differs from passed evidence'

current_state="$(classify_generation_state)"
for unit in "${guarded_transient_units[@]}"; do
  if [[ "$current_state" == ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED &&
    ("$unit" == "$rollback_unit.timer" || "$unit" == "$rollback_unit.service") ]]; then
    continue
  fi
  load_state="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
  [[ -z "$load_state" || "$load_state" == not-found ]] ||
    die "transient rollback unit remains loaded: $unit ($load_state)"
done

if [[ "$current_state" == ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED ]]; then
  assert_recovery_absent
  load_resume_snapshot
  assert_resume_timer
  timer_armed=true
  mutation_started=true
  assert_generation_three
  assert_protected_units "$snapshot/services.before.txt"
  assert_health
  sha256sum -c "$snapshot/protected-files.before.sha256" >/dev/null ||
    die 'a protected file changed during the in-flight restoration'
  assert_recovery_absent
  stop_restoration_timer
  assert_generation_three
  pass restoration 'resumed exact in-flight restoration and retained generation three after verified postflight'
  printf '%s\n' \
    "SNAPSHOT_STAMP=$stamp" \
    'NO REBOOT: restoration performed no reboot and recovery remains separately gated.'
  exit 0
fi

[[ "$current_state" == ACTIVE_REGISTERED_GENERATION_TWO_TRIPLE_RETAINED ]] ||
  die "expected exact generation two or resumable generation three; observed $current_state"
assert_generation_two
assert_recovery_absent
assert_nix_runtime_ready
assert_health
seat_can_graphical="$(loginctl show-seat seat0 -p CanGraphical --value 2>/dev/null || true)"
seat_active_session="$(loginctl show-seat seat0 -p ActiveSession --value 2>/dev/null || true)"
[[ "$seat_can_graphical" == yes && -n "$seat_active_session" ]] ||
  die 'seat0 does not expose an active graphical local-console recovery session'

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
snapshot=$snapshot_root/$stamp
path_exists "$snapshot" && die "refusing existing restoration snapshot path: $snapshot"
umask 077
install -d -m 0700 "$snapshot"
property_parser=$snapshot/systemd-snapshot-property.sh
install -m 0700 "$transaction_source" "$snapshot/root-boot-persistence-transaction.sh"
install -m 0700 "$property_parser_source" "$property_parser"
transaction=$snapshot/root-boot-persistence-transaction.sh
install -m 0600 "$state_path" "$snapshot/manager-state.before.json"
sha256sum /etc/nix/nix.conf /etc/passwd /etc/group /etc/shadow >"$snapshot/protected-files.before.sha256"
systemctl show "${protected_units[@]}" nix-daemon.socket \
  -p Id -p LoadState -p ActiveState -p SubState -p FragmentPath -p MainPID \
  -p ActiveEnterTimestampMonotonic -p NeedDaemonReload -p Result --no-pager \
  >"$snapshot/services.before.txt"
{
  printf 'schema=1\n'
  printf 'purpose=restore-generation-three-after-verified-recovery-rollback\n'
  printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'host=sparkle-01\n'
  printf 'repo_commit=%s\n' "$repo_commit"
  printf 'restore_program_sha256=%s\n' "$self_sha"
  printf 'transaction_sha256=%s\n' "$transaction_sha256"
  printf 'generation_one=%s\n' "$generation_one"
  printf 'generation_two=%s\n' "$generation_two"
  printf 'generation_three=%s\n' "$generation_three"
  printf 'prestate=ACTIVE_REGISTERED_GENERATION_TWO_TRIPLE_RETAINED\n'
} >"$snapshot/context.txt"
(
  cd "$snapshot"
  sha256sum context.txt manager-state.before.json protected-files.before.sha256 \
    services.before.txt root-boot-persistence-transaction.sh \
    systemd-snapshot-property.sh >SHA256SUMS
)
printf 'Snapshot creation completed.\n' >"$snapshot/SNAPSHOT_COMPLETE"
pass snapshot "$snapshot is complete, private, checksum-valid, and bound to the exact rollback state"

assert_generation_two
assert_recovery_absent
assert_protected_units "$snapshot/services.before.txt"
assert_health
sha256sum -c "$snapshot/protected-files.before.sha256" >/dev/null ||
  die 'a protected file changed after the restoration snapshot'

printf '\n%s\n' \
  'Restoration preflight passed. Verify the physical keyboard/display/local terminal.' \
  'Press Enter once to arm a ten-minute rollback and restore generation three.' \
  'No exact phrase is required; Ctrl-C or timeout makes no changes.' \
  'This command will not reboot the host.'
printf '> '
IFS= read -r -t 300 _ || die 'restoration acknowledgement timed out before mutation'

systemd-run \
  --unit="$rollback_unit" \
  --description='Timed rollback for DGX generation-three restoration' \
  --collect --service-type=exec --on-active=10m --timer-property=AccuracySec=1s \
  "$transaction" rollback-boot \
  "$generation_one" "$generation_two" "$generation_three" >/dev/null ||
  die 'could not establish exact generation-two rollback timer'
timer_armed=true
assert_resume_timer
pass rollback 'ten-minute exact generation-two rollback is active before mutation'

mutation_started=true
"$transaction" apply-boot "$generation_one" "$generation_two" "$generation_three"
assert_generation_three
assert_protected_units "$snapshot/services.before.txt"
assert_health
sha256sum -c "$snapshot/protected-files.before.sha256" >/dev/null ||
  die 'restoration changed a protected file'
assert_generation_three
assert_protected_units "$snapshot/services.before.txt"
assert_health
sha256sum -c "$snapshot/protected-files.before.sha256" >/dev/null ||
  die 'a protected file changed during repeated restoration postflight'
assert_recovery_absent
stop_restoration_timer
assert_generation_three
pass restoration 'exact generation three is automatically retained, live, and boot-linked after repeated postflight'
printf '%s\n' \
  "SNAPSHOT_STAMP=$stamp" \
  'NO REBOOT: restoration performed no reboot and recovery remains separately gated.'
