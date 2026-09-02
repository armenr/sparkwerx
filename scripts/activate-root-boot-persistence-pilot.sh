#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
self_source=$repo_dir/scripts/activate-root-boot-persistence-pilot.sh
generation_one=/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager
generation_two=/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager
generation_three=/nix/store/w8kn2idc0ix6x1024qphv2fvmaf664d7-system-manager
transaction_sha256=53eb8c4d03a4c24764f519e358f3c5c813e66f189efc07e50f82cd19841d8288
test_drv=/nix/store/i5skjqyw16qgbvb4azr68msrqfz64d7k-container-test-dgx-root-canary-boot-persistence-transaction.drv
test_output=/nix/store/d3ymf91l07rvai5pzz9ygj3vl3g9xss3-container-test-dgx-root-canary-boot-persistence-transaction
test_output_hash=sha256:0lxm3pjsd4yy9zl49zx6cbydc9iid1i7mdrajkinkfzszg5k7ikn
nix_bin=/nix/var/nix/profiles/default/bin/nix
nix_store_bin=/nix/var/nix/profiles/default/bin/nix-store
state_path=/var/lib/system-manager/state/system-manager-state.json
profile_dir=/nix/var/nix/profiles/system-manager-profiles
profile_path=$profile_dir/system-manager
generation_one_path=$profile_dir/system-manager-1-link
generation_two_path=$profile_dir/system-manager-2-link
generation_three_path=$profile_dir/system-manager-3-link
gcroot_path=/nix/var/nix/gcroots/system-manager-current
pilot_root=/nix/var/nix/gcroots/dgx-setup-root-canary-pilot
generation_two_root=/nix/var/nix/gcroots/dgx-setup-root-canary-generation-two-pilot
generation_three_root=/nix/var/nix/gcroots/dgx-setup-root-canary-boot-persistence-pilot
boot_link=/etc/systemd/system/default.target.wants/system-manager.target
rollback_unit=dgx-root-boot-persistence-rollback

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
  dgx-root-generation-switch-rollback.timer
  dgx-root-generation-switch-rollback.service
  $rollback_unit.timer
  $rollback_unit.service
)

timer_armed=false
generation_three_root_created=false
activation_started=false
snapshot_age=UNKNOWN

usage() {
  printf 'Usage: sudo %s /absolute/private/boot-persistence-snapshot-directory\n' \
    "$(basename "$0")" >&2
}

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

on_exit() {
  local status="$?"

  if ((status != 0)); then
    if [[ "$timer_armed" == true ]]; then
      printf '%s\n' \
        "ROLLBACK ARMED: keep all three pilot roots; $rollback_unit.timer will restore exact live no-boot generation two." \
        >&2
    elif [[ "$activation_started" == true ]]; then
      printf '%s\n' \
        "WARNING: activation started without a known armed timer; from the console run: $transaction rollback-boot $generation_one $generation_two $generation_three" \
        >&2
    elif [[ "$generation_three_root_created" == true ]]; then
      printf '%s\n' \
        "NO ACTIVATION STARTED: exact generation-three retention was created and left at $generation_three_root for explicit verification/cleanup." \
        >&2
    fi
  fi
}
trap on_exit EXIT

path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

require_commands() {
  local command_name

  for command_name in \
    awk bash cmp date find git grep hostname jq ln nvidia-smi readlink \
    sed sha256sum sort stat systemctl systemd-run tailscale timeout; do
    command -v "$command_name" >/dev/null 2>&1 ||
      die "required command is unavailable: $command_name"
  done
}

context_value() {
  local key="$1"

  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' \
    "$snapshot/context.txt"
}

assert_snapshot_fresh() {
  local snapshot_timestamp snapshot_epoch now_epoch

  snapshot_timestamp="$(context_value timestamp_utc)"
  snapshot_epoch="$(date -d "$snapshot_timestamp" +%s 2>/dev/null || true)"
  now_epoch="$(date +%s)"
  [[ -n "$snapshot_epoch" ]] || die "snapshot timestamp is missing or invalid"
  snapshot_age=$((now_epoch - snapshot_epoch))
  ((snapshot_age >= 0 && snapshot_age <= 1800)) ||
    die "snapshot is not in the current 30-minute boot-persistence window (age=${snapshot_age}s)"
}

snapshot_property() {
  local unit="$1"
  local property="$2"

  "$property_parser" "$snapshot/services.before.txt" "$unit" "$property"
}

assert_protected_units() {
  local unit
  local before_load current_load before_active current_active
  local before_substate current_substate before_reload current_reload
  local before_fragment current_fragment before_pid current_pid
  local before_started current_started

  for unit in "${protected_units[@]}"; do
    before_load="$(snapshot_property "$unit" LoadState)"
    current_load="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
    before_active="$(snapshot_property "$unit" ActiveState)"
    current_active="$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)"
    before_substate="$(snapshot_property "$unit" SubState)"
    current_substate="$(systemctl show "$unit" -p SubState --value 2>/dev/null || true)"
    before_reload="$(snapshot_property "$unit" NeedDaemonReload)"
    current_reload="$(systemctl show "$unit" -p NeedDaemonReload --value 2>/dev/null || true)"
    before_fragment="$(snapshot_property "$unit" FragmentPath)"
    current_fragment="$(systemctl show "$unit" -p FragmentPath --value 2>/dev/null || true)"
    before_pid="$(snapshot_property "$unit" MainPID)"
    current_pid="$(systemctl show "$unit" -p MainPID --value 2>/dev/null || true)"
    before_started="$(snapshot_property "$unit" ActiveEnterTimestampMonotonic)"
    current_started="$(
      systemctl show "$unit" -p ActiveEnterTimestampMonotonic --value \
        2>/dev/null || true
    )"

    [[ "$before_load" == loaded && "$current_load" == loaded ]] ||
      die "$unit is not loaded exactly as snapshotted"
    [[ "$before_active" == active && "$current_active" == active ]] ||
      die "$unit is not active exactly as snapshotted"
    [[ -n "$before_substate" && "$current_substate" == "$before_substate" ]] ||
      die "$unit changed SubState"
    [[ "$before_reload" == no && "$current_reload" == no ]] ||
      die "$unit has a pending daemon reload"
    [[ -n "$before_fragment" && "$current_fragment" == "$before_fragment" ]] ||
      die "$unit changed FragmentPath"
    [[ -n "$before_pid" && "$current_pid" == "$before_pid" ]] ||
      die "$unit changed MainPID"
    [[ -n "$before_started" && "$current_started" == "$before_started" ]] ||
      die "$unit changed active-enter timestamp"
  done

  pass protected_units "all seven factory/access services remain active, unrestarted, loaded from their original fragments, with no pending reload"
}

assert_system_health() {
  local system_state failed_units gpu_state

  system_state="$(systemctl is-system-running 2>/dev/null || true)"
  [[ "$system_state" == running ]] ||
    die "systemd state is ${system_state:-UNKNOWN}, not running"
  failed_units="$(
    systemctl --failed --no-legend --plain 2>/dev/null |
      sed '/^[[:space:]]*$/d' || true
  )"
  [[ -z "$failed_units" ]] || die "systemd reports one or more failed units"
  gpu_state="$(
    nvidia-smi \
      --query-gpu=name,driver_version,pstate,temperature.gpu \
      --format=csv,noheader 2>/dev/null || true
  )"
  [[ -n "$gpu_state" ]] || die "nvidia-smi query failed"

  pass system_health "systemd=running;failed_units=0;gpu=$gpu_state"
}

assert_tailscale_health() {
  local status_json prefs_json backend online want_running run_ssh

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
    die "Tailscale health failed: backend=$backend;online=$online;WantRunning=$want_running;RunSSH=$run_ssh"

  pass tailscale "backend=$backend;online=$online;WantRunning=$want_running;RunSSH=$run_ssh"
}

assert_exact_manager_state() {
  local boot_enabled="$1"

  jq -e --argjson boot_enabled "$boot_enabled" '
    ((keys | sort) == ["fileTree", "services", "version"]) and
    (.version == 1) and
    ((.fileTree | keys | sort) == ["backedUpFiles", "files"]) and
    ((.fileTree.files | sort) == (([
        "/etc/dgx-setup/canary",
        "/etc/systemd/system/dgx-setup-canary.service",
        "/etc/systemd/system/sysinit-reactivation.target",
        "/etc/systemd/system/system-manager.target",
        "/etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service"
      ] + (if $boot_enabled then [
        "/etc/systemd/system/default.target.wants/system-manager.target"
      ] else [] end)) | sort)) and
    (.fileTree.backedUpFiles == []) and
    ((.services | keys | sort) == [
      "dgx-setup-canary.service",
      "sysinit-reactivation.target",
      "system-manager.target"
    ])
  ' "$state_path" >/dev/null ||
    die "System Manager state exceeds or differs from the exact reviewed boot boundary"
}

assert_managed_links_match_snapshot() {
  local index=0 kind path expected extra

  while IFS='|' read -r kind path expected extra; do
    [[ "$index" -lt "${#managed_paths[@]}" ]] ||
      die "snapshot managed-link inventory has unexpected extra records"
    [[ "$kind" == EXACT_SYMLINK && -z "$extra" ]] ||
      die "snapshot managed-link record is malformed"
    [[ "$path" == "${managed_paths[$index]}" ]] ||
      die "snapshot managed-link order/path differs from the reviewed surface"
    [[ -L "$path" && "$(readlink -f -- "$path" 2>/dev/null || true)" == "$expected" ]] ||
      die "live managed link differs from the snapshot: $path"
    index=$((index + 1))
  done <"$snapshot/managed-links.before.tsv"

  [[ "$index" -eq "${#managed_paths[@]}" ]] ||
    die "snapshot managed-link inventory is incomplete"
}

assert_snapshot_registration_inventory() {
  local -a records=()

  mapfile -t records <"$snapshot/registration.before.tsv"
  [[ "${#records[@]}" -eq 11 ]] ||
    die "snapshot registration inventory must contain exactly eleven records"
  [[ "${records[0]}" == "EXACT_DIRECTORY|$profile_dir" ]] ||
    die "snapshot profile-directory record is not exact"
  [[ "${records[1]}" == "EXACT_SYMLINK|$profile_path|system-manager-2-link|$generation_two" ]] ||
    die "snapshot selected-profile record is not exact generation two"
  [[ "${records[2]}" == "EXACT_SYMLINK|$generation_one_path|$generation_one|$generation_one" ]] ||
    die "snapshot generation-one link record is not exact"
  [[ "${records[3]}" == "EXACT_SYMLINK|$generation_two_path|$generation_two|$generation_two" ]] ||
    die "snapshot generation-two link record is not exact"
  [[ "${records[4]}" == "ABSENT|$generation_three_path" ]] ||
    die "snapshot did not record generation three absent"
  [[ "${records[5]}" == "EXACT_SYMLINK|$gcroot_path|$generation_two|$generation_two" ]] ||
    die "snapshot upstream-root record is not exact generation two"
  [[ "${records[6]}" == "EXACT_SYMLINK|$pilot_root|$generation_one|$generation_one" ]] ||
    die "snapshot generation-one pilot-root record is not exact"
  [[ "${records[7]}" == "EXACT_SYMLINK|$generation_two_root|$generation_two|$generation_two" ]] ||
    die "snapshot generation-two pilot-root record is not exact"
  [[ "${records[8]}" == "ABSENT|$generation_three_root" ]] ||
    die "snapshot did not record generation-three pilot root absent"
  [[ "${records[9]}" == "ABSENT|$boot_link" ]] ||
    die "snapshot did not record the host boot edge absent"
  [[ "${records[10]}" == "ACTIVE_REGISTERED_GENERATION_TWO_RETAINED|$state_path" ]] ||
    die "snapshot did not record exact registered/live generation two"
}

assert_snapshot() {
  local snapshot_commit current_commit current_status
  local snapshot_helper_sha snapshot_wrapper_sha snapshot_parser_sha
  local snapshot_parser_test_sha
  local -a expected_files observed_files

  expected_files=(
    SHA256SUMS
    SNAPSHOT_COMPLETE
    context.txt
    managed-links.before.tsv
    manager-state.before.json
    protected-files.before.sha256
    registration.before.tsv
    root-boot-persistence-transaction.sh
    sanitized-health.before.txt
    services.before.txt
    systemd-snapshot-property.sh
  )
  mapfile -t observed_files < <(
    find "$snapshot" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort
  )
  mapfile -t expected_files < <(printf '%s\n' "${expected_files[@]}" | sort)
  [[ "${observed_files[*]}" == "${expected_files[*]}" ]] ||
    die "snapshot contains a missing or unexpected top-level file"

  [[ "$(<"$snapshot/SNAPSHOT_COMPLETE")" == "Snapshot creation completed." ]] ||
    die "snapshot completion marker is invalid"
  [[ "$(stat -c %u "$snapshot")" == 0 && "$(stat -c %a "$snapshot")" == 700 ]] ||
    die "snapshot must be root-owned and mode 0700"
  (
    cd "$snapshot"
    sha256sum -c SHA256SUMS >/dev/null
  ) || die "snapshot checksum verification failed"

  for exact_record in \
    schema=1 \
    purpose=system-manager-boot-persistence \
    host=sparkle-01 \
    generation_one="$generation_one" \
    generation_two="$generation_two" \
    generation_three="$generation_three" \
    transaction_sha256="$transaction_sha256" \
    test_drv="$test_drv" \
    test_output="$test_output" \
    test_output_hash="$test_output_hash" \
    nix_version=2.35.2; do
    grep -Fx "$exact_record" "$snapshot/context.txt" >/dev/null ||
      die "snapshot context is missing exact record: $exact_record"
  done

  snapshot_helper_sha="$(context_value snapshot_program_sha256)"
  [[ -n "$snapshot_helper_sha" &&
    "$snapshot_helper_sha" == "$(sha256sum "$repo_dir/scripts/snapshot-root-boot-persistence.sh" | awk '{print $1}')" ]] ||
    die "snapshot helper differs from the exact snapshotted program"
  snapshot_wrapper_sha="$(context_value live_wrapper_sha256)"
  [[ -n "$snapshot_wrapper_sha" &&
    "$snapshot_wrapper_sha" == "$(sha256sum "$self_source" | awk '{print $1}')" ]] ||
    die "live wrapper differs from the exact snapshotted program"
  snapshot_parser_sha="$(context_value property_parser_sha256)"
  property_parser=$snapshot/systemd-snapshot-property.sh
  [[ -n "$snapshot_parser_sha" &&
    "$snapshot_parser_sha" == "$(sha256sum "$property_parser" | awk '{print $1}')" &&
    "$snapshot_parser_sha" == "$(sha256sum "$repo_dir/scripts/systemd-snapshot-property.sh" | awk '{print $1}')" ]] ||
    die "systemd snapshot parser differs from the exact snapshotted/repository program"
  snapshot_parser_test_sha="$(context_value property_parser_test_sha256)"
  [[ -n "$snapshot_parser_test_sha" &&
    "$snapshot_parser_test_sha" == "$(sha256sum "$repo_dir/scripts/test-systemd-snapshot-property.sh" | awk '{print $1}')" ]] ||
    die "systemd snapshot parser test differs from the exact snapshotted program"
  snapshot_policy_drv="$(context_value root_policy_drv)"
  [[ -n "$snapshot_policy_drv" ]] ||
    die "snapshot does not identify its exact root-manager policy derivation"

  transaction=$snapshot/root-boot-persistence-transaction.sh
  for program in "$transaction" "$property_parser"; do
    [[ "$(stat -c %u "$program")" == 0 && "$(stat -c %a "$program")" == 700 ]] ||
      die "snapshot program must be root-owned and mode 0700: $program"
    bash -n "$program" || die "snapshot program failed syntax validation: $program"
  done
  [[ "$(sha256sum "$transaction" | awk '{print $1}')" == "$transaction_sha256" &&
    "$(sha256sum "$repo_dir/scripts/root-boot-persistence-transaction.sh" | awk '{print $1}')" == "$transaction_sha256" ]] ||
    die "transaction differs from the exact passed/snapshotted program"

  assert_snapshot_fresh

  snapshot_commit="$(context_value repo_commit)"
  current_commit="$(git -C "$repo_dir" rev-parse HEAD)"
  current_status="$(git -C "$repo_dir" status --porcelain --untracked-files=all)"
  [[ -n "$snapshot_commit" && "$current_commit" == "$snapshot_commit" ]] ||
    die "repository commit changed after the snapshot"
  [[ -z "$current_status" ]] ||
    die "repository must remain clean for the boot-persistence activation"

  for store_path in \
    "$generation_one" "$generation_two" "$generation_three" \
    "$test_drv" "$test_output"; do
    "$nix_store_bin" --check-validity "$store_path" >/dev/null 2>&1 ||
      die "required exact Nix store path is invalid: $store_path"
  done
  "$nix_store_bin" --check-validity "$snapshot_policy_drv" >/dev/null 2>&1 ||
    die "snapshotted root-manager fixed-hash policy derivation is invalid"
  [[ "$($nix_store_bin --query --deriver "$test_output")" == "$test_drv" ]] ||
    die "boot-persistence test output has an unexpected deriver"
  [[ "$($nix_store_bin --query --hash "$test_output")" == "$test_output_hash" ]] ||
    die "boot-persistence test output hash differs from passed evidence"

  assert_snapshot_registration_inventory
  cmp -s "$state_path" "$snapshot/manager-state.before.json" ||
    die "live manager state changed after the snapshot"
  sha256sum -c "$snapshot/protected-files.before.sha256" >/dev/null ||
    die "a protected account/Nix file changed after the snapshot"

  pass snapshot "$snapshot is complete, private, checksum-valid, ${snapshot_age}s old, and bound to the exact candidates/transaction/test/pre-state"
}

assert_current_flake_evidence() {
  local current_generation_one current_generation_two current_generation_three
  local current_test_drv current_test_output
  local current_policy_drv manifest_json snapshot_sha wrapper_sha parser_sha parser_test_sha

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
  current_generation_three="$(
    "$nix_bin" --extra-experimental-features "nix-command flakes" \
      eval --raw --no-write-lock-file \
      .#packages.aarch64-linux.root-system-canary-generation-three-boot.outPath
  )"
  current_test_drv="$(
    "$nix_bin" --extra-experimental-features "nix-command flakes" \
      eval --raw --no-write-lock-file \
      .#checks.aarch64-linux.root-canary-boot-persistence-transaction-container.drvPath
  )"
  current_test_output="$(
    "$nix_bin" --extra-experimental-features "nix-command flakes" \
      eval --raw --no-write-lock-file \
      .#checks.aarch64-linux.root-canary-boot-persistence-transaction-container.outPath
  )"
  current_policy_drv="$(
    "$nix_bin" --extra-experimental-features "nix-command flakes" \
      eval --raw --no-write-lock-file \
      .#checks.aarch64-linux.root-manager-policy.drvPath
  )"
  [[ "$current_generation_one" == "$generation_one" &&
    "$current_generation_two" == "$generation_two" &&
    "$current_generation_three" == "$generation_three" &&
    "$current_test_drv" == "$test_drv" &&
    "$current_test_output" == "$test_output" ]] ||
    die "current flake no longer matches the exact candidates/passed test"
  "$nix_store_bin" --check-validity "$current_policy_drv" >/dev/null 2>&1 ||
    die "current root-manager fixed-hash policy derivation is invalid"
  [[ "$current_policy_drv" == "$snapshot_policy_drv" ]] ||
    die "root-manager fixed-hash policy derivation changed after the snapshot"

  snapshot_sha="$(sha256sum "$repo_dir/scripts/snapshot-root-boot-persistence.sh" | awk '{print $1}')"
  wrapper_sha="$(sha256sum "$self_source" | awk '{print $1}')"
  parser_sha="$(sha256sum "$repo_dir/scripts/systemd-snapshot-property.sh" | awk '{print $1}')"
  parser_test_sha="$(sha256sum "$repo_dir/scripts/test-systemd-snapshot-property.sh" | awk '{print $1}')"
  manifest_json="$(
    "$nix_bin" --extra-experimental-features "nix-command flakes" \
      eval --json --no-write-lock-file .#lib.dgxRootManagerManifest.aarch64-linux
  )"
  jq -e \
    --arg generation_one "$generation_one" \
    --arg generation_two "$generation_two" \
    --arg generation_three "$generation_three" \
    --arg snapshot_sha "$snapshot_sha" \
    --arg wrapper_sha "$wrapper_sha" \
    --arg parser_sha "$parser_sha" \
    --arg parser_test_sha "$parser_test_sha" '
      .bootPersistence.status ==
        "live-pilot-designed-activation-not-authorized" and
      .bootPersistence.exactCandidates.generationOne ==
        $generation_one and
      .bootPersistence.exactCandidates.generationTwo ==
        $generation_two and
      .bootPersistence.exactCandidates.generationThree ==
        $generation_three and
      .bootPersistence.retention.hostCreated == false and
      .bootPersistence.livePilot.status ==
        "repository-design-complete-not-run" and
      .bootPersistence.livePilot.snapshotProgram.sha256 ==
        $snapshot_sha and
      .bootPersistence.livePilot.activationProgram.sha256 ==
        $wrapper_sha and
      .bootPersistence.livePilot.systemdSnapshotPropertyProgram.sha256 ==
        $parser_sha and
      .bootPersistence.livePilot.systemdSnapshotPropertyTest.sha256 ==
        $parser_test_sha and
      .bootPersistence.livePilot.hostCandidateRetentionPerformed == false and
      .bootPersistence.livePilot.hostRegistrationPerformed == false and
      .bootPersistence.livePilot.hostActivationPerformed == false and
      .bootPersistence.livePilot.hostBootLinkCreated == false and
      .bootPersistence.livePilot.hostRebootPerformed == false
    ' >/dev/null <<<"$manifest_json" ||
    die "current root-manager manifest does not match the reviewed, unrun live-pilot design"
}

assert_generation_two_prestate() {
  local state_class unit load_state

  [[ "$(hostname)" == sparkle-01 ]] ||
    die "this pilot is scoped to sparkle-01"
  [[ "$($nix_bin --version)" == "nix (Nix) 2.35.2" ]] ||
    die "active root-profile Nix is not exact reviewed 2.35.2"
  assert_current_flake_evidence

  state_class="$(
    "$repo_dir/scripts/audit-root-canary-state.sh" \
      "$generation_two" registered-second "$generation_one" 2>/dev/null || true
  )"
  [[ "$state_class" == ACTIVE_REGISTERED_GENERATION_TWO_RETAINED ]] ||
    die "expected exact registered/live generation two; observed ${state_class:-UNKNOWN}"
  if path_exists "$generation_three_root"; then
    die "generation-three pilot root already exists before this transaction"
  fi
  if path_exists "$generation_three_path"; then
    die "generation-three profile link already exists before this transaction"
  fi
  if path_exists "$boot_link"; then
    die "boot linkage exists before the boot-persistence activation"
  fi

  for unit in "${guarded_transient_units[@]}"; do
    load_state="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
    [[ -z "$load_state" || "$load_state" == not-found ]] ||
      die "transient rollback unit is unexpectedly loaded: $unit ($load_state)"
  done

  cmp -s "$state_path" "$snapshot/manager-state.before.json" ||
    die "live manager state differs from the snapshot"
  assert_managed_links_match_snapshot
  assert_exact_manager_state false
  sha256sum -c "$snapshot/protected-files.before.sha256" >/dev/null ||
    die "a protected account/Nix file changed after the snapshot"
  assert_protected_units
  assert_system_health
  assert_tailscale_health
  pass preflight "exact registered/live no-boot generation two is unchanged; generation three remains absent"
}

assert_generation_two_with_third_retention() {
  "$transaction" verify-before \
    "$generation_one" "$generation_two" "$generation_three" >/dev/null ||
    die "transaction rejected generation two after exact generation-three retention"
  cmp -s "$state_path" "$snapshot/manager-state.before.json" ||
    die "candidate retention changed live manager state"
  assert_managed_links_match_snapshot
  sha256sum -c "$snapshot/protected-files.before.sha256" >/dev/null ||
    die "candidate retention changed a protected account/Nix file"
  pass retention "generation three is directly retained; generation two remains selected, extra-rooted, live, and not boot-linked"
}

assert_generation_three_state() {
  "$transaction" verify-after \
    "$generation_one" "$generation_two" "$generation_three" >/dev/null ||
    die "transaction verifier rejected registered/live boot generation three"
  assert_exact_manager_state true
  grep -Fx 'registration-test-generation=2' /etc/dgx-setup/canary >/dev/null ||
    die "live canary lacks the inherited generation-two marker"
  grep -Fx 'boot-persistence-generation=3' /etc/dgx-setup/canary >/dev/null ||
    die "live canary lacks the exact generation-three boot marker"
  [[ -L "$pilot_root" && "$(readlink -- "$pilot_root")" == "$generation_one" ]] ||
    die "generation-one pilot root changed"
  [[ -L "$generation_two_root" && "$(readlink -- "$generation_two_root")" == "$generation_two" ]] ||
    die "generation-two pilot root changed"
  [[ -L "$generation_three_root" && "$(readlink -- "$generation_three_root")" == "$generation_three" ]] ||
    die "generation-three pilot root changed"
  [[ -L "$boot_link" ]] ||
    die "exact candidate-managed boot edge is absent"
  sha256sum -c "$snapshot/protected-files.before.sha256" >/dev/null ||
    die "boot-persistence activation changed a protected account/Nix file"
  assert_protected_units
  assert_system_health
  assert_tailscale_health
  pass post_activation "exact generation three is selected, extra-rooted, live, and boot-linked; generations one/two and all pilot roots remain"
}

if [[ "$EUID" -ne 0 ]]; then
  die "run this helper with sudo"
fi
if [[ "$#" -ne 1 ]]; then
  usage
  exit 2
fi

PATH=/nix/var/nix/profiles/default/bin:/usr/sbin:/usr/bin:/sbin:/bin
NIX_USER_CONF_FILES=/dev/null
export PATH NIX_USER_CONF_FILES
require_commands
[[ -x "$nix_bin" && -x "$nix_store_bin" ]] ||
  die "reviewed root-profile Nix tools are unavailable"
cd "$repo_dir"

[[ "$(readlink -f -- "${BASH_SOURCE[0]}")" == "$self_source" ]] ||
  die "run the exact repository boot-persistence wrapper, not a copy or symlink"
snapshot="$(readlink -f -- "$1")"
case "$snapshot" in
  "$repo_dir"/inventory/sparkle-01/raw/system-manager-boot-persistence/*)
    ;;
  *)
    die "snapshot must be below $repo_dir/inventory/sparkle-01/raw/system-manager-boot-persistence"
    ;;
esac
[[ -t 0 && -t 1 ]] ||
  die "run this guarded boot-persistence activation from an interactive terminal"

printf '# DGX System Manager boot-persistence pilot\n'
printf '# timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
info generation_one "$generation_one"
info generation_two "$generation_two"
info generation_three "$generation_three"
info retention "$pilot_root;$generation_two_root;$generation_three_root"
info rollback "$rollback_unit.timer;10 minutes;exact registered/live no-boot generation-two rollback"
info unchanged "factory/access service ownership and processes;/run/current-system;host reboot"

assert_snapshot
assert_generation_two_prestate
assert_snapshot_fresh
pass freshness "snapshot remains in-window immediately before candidate retention (age=${snapshot_age}s)"

ln -s -- "$generation_three" "$generation_three_root" ||
  die "could not create exact generation-three pilot root"
generation_three_root_created=true
[[ -L "$generation_three_root" &&
  "$(readlink -- "$generation_three_root")" == "$generation_three" ]] ||
  die "generation-three pilot root target verification failed"
assert_generation_two_with_third_retention

if ! systemd-run \
  --unit="$rollback_unit" \
  --description="Timed rollback for DGX System Manager boot-persistence activation" \
  --collect \
  --service-type=exec \
  --on-active=10m \
  --timer-property=AccuracySec=1s \
  "$transaction" rollback-boot \
  "$generation_one" "$generation_two" "$generation_three"; then
  if [[ "$(systemctl show "$rollback_unit.timer" -p ActiveState --value 2>/dev/null || true)" == active ]]; then
    timer_armed=true
  fi
  die "could not establish the exact no-boot generation-two rollback timer"
fi
timer_armed=true

[[ "$(systemctl show "$rollback_unit.timer" -p ActiveState --value 2>/dev/null || true)" == active ]] ||
  die "rollback timer is not active"
[[ "$(systemctl show "$rollback_unit.timer" -p SubState --value 2>/dev/null || true)" == waiting ]] ||
  die "rollback timer is not waiting"
exec_start="$(systemctl show "$rollback_unit.service" -p ExecStart --value --no-pager)"
for expected_arg in \
  "$transaction" rollback-boot \
  "$generation_one" "$generation_two" "$generation_three"; do
  grep -F -- "$expected_arg" <<<"$exec_start" >/dev/null ||
    die "rollback service does not contain exact argument: $expected_arg"
done
pass rollback "timer is active/waiting and bound to exact registered/live no-boot generation-two rollback"
info rollback_schedule "$(
  systemctl list-timers --all --no-legend --no-pager "$rollback_unit.timer" |
    sed 's/^[[:space:]]*//; s/[[:space:]][[:space:]]*/ /g'
)"

activation_started=true
"$transaction" apply-boot "$generation_one" "$generation_two" "$generation_three"
assert_generation_three_state

printf '\n%s\n' \
  'Automatic postflight passed. Verify the physical keyboard/display/local terminal still works.' \
  'Do not reboot during this activation window. Keep this terminal alive too.' \
  'Within five minutes, type exactly KEEP GENERATION THREE.' \
  'Any other input, Ctrl-C, disconnect, or timeout leaves the ten-minute generation-two rollback armed.' \
  "Immediate manual rollback is: $transaction rollback-boot $generation_one $generation_two $generation_three" \
  'Rollback restores registered/live no-boot generation two and deliberately keeps all three exact pilot roots.'
printf '> '

console_reply=
if ! read -r -t 300 console_reply; then
  die "local-console confirmation timed out; leaving generation-two rollback armed"
fi
[[ "$console_reply" == "KEEP GENERATION THREE" ]] ||
  die "confirmation did not match; leaving generation-two rollback armed"

assert_generation_three_state
systemctl stop "$rollback_unit.timer"
timer_state="$(systemctl show "$rollback_unit.timer" -p ActiveState --value 2>/dev/null || true)"
[[ -z "$timer_state" || "$timer_state" == inactive ]] ||
  die "rollback timer did not become inactive after confirmed postflight"
timer_armed=false

"$transaction" verify-after \
  "$generation_one" "$generation_two" "$generation_three" >/dev/null ||
  die "generation-three state changed while disarming rollback"
[[ -L "$pilot_root" && "$(readlink -- "$pilot_root")" == "$generation_one" ]] ||
  die "generation-one pilot root changed while disarming rollback"
[[ -L "$generation_two_root" && "$(readlink -- "$generation_two_root")" == "$generation_two" ]] ||
  die "generation-two pilot root changed while disarming rollback"
[[ -L "$generation_three_root" && "$(readlink -- "$generation_three_root")" == "$generation_three" ]] ||
  die "generation-three pilot root changed while disarming rollback"

pass boot_persistence "generation three retained after repeated postflight and independent local-console confirmation"
printf '%s\n' \
  'KEEP: all three direct pilot roots remain required for exact rollback.' \
  "REGISTERED/LIVE: $profile_path and $gcroot_path point to exact generation three; the one reviewed boot edge is active." \
  'NOT DONE: no host reboot, post-reboot proof, broader root role, desktop switch, Tailscale migration, or pilot-root cleanup occurred.'
