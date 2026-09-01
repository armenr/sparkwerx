#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
candidate=/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager
transaction_sha256=86c4be22ed350782920905897d80616b3949998d2662fd04ab9d1f5c3f4078a9
rollback_unit=dgx-root-registration-rollback
state_path=/var/lib/system-manager/state/system-manager-state.json
profile_dir=/nix/var/nix/profiles/system-manager-profiles
profile_path=$profile_dir/system-manager
generation_one_path=$profile_dir/system-manager-1-link
gcroot_path=/nix/var/nix/gcroots/system-manager-current
pilot_root=/nix/var/nix/gcroots/dgx-setup-root-canary-pilot

protected_units=(
  nix-daemon.service
  tailscaled.service
  gdm.service
  docker.service
  dgx-dashboard.service
  dgx-dashboard-admin.service
  nvidia-persistenced.service
)

timer_armed=false
registration_started=false

usage() {
  printf 'Usage: sudo %s /absolute/private/registration-snapshot-directory\n' \
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
        "ROLLBACK ARMED: $rollback_unit.timer will remove only the exact first-generation profile and extra GC root; it will not deactivate the live canary or remove $pilot_root." \
        >&2
    elif [[ "$registration_started" == true ]]; then
      printf '%s\n' \
        "WARNING: registration started without a known armed timer; run the snapshot's exact root-registration-transaction.sh rollback-first command from the console." \
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
    awk bash cmp date find git grep hostname jq nvidia-smi readlink sed \
    sha256sum sort stat systemctl systemd-run tailscale timeout; do
    command -v "$command_name" >/dev/null 2>&1 ||
      die "required command is unavailable: $command_name"
  done
}

snapshot_property() {
  local unit="$1"
  local property="$2"

  awk -F= -v wanted="$unit" -v property="$property" '
    $1 == "Id" { selected = ($2 == wanted) }
    selected && $1 == property {
      sub("^[^=]*=", "")
      print
      exit
    }
  ' "$snapshot/services.before.txt"
}

assert_protected_units() {
  local unit active reload before_fragment current_fragment
  local before_pid current_pid before_started current_started

  for unit in "${protected_units[@]}"; do
    active="$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)"
    reload="$(systemctl show "$unit" -p NeedDaemonReload --value 2>/dev/null || true)"
    before_fragment="$(snapshot_property "$unit" FragmentPath)"
    current_fragment="$(systemctl show "$unit" -p FragmentPath --value 2>/dev/null || true)"
    before_pid="$(snapshot_property "$unit" MainPID)"
    current_pid="$(systemctl show "$unit" -p MainPID --value 2>/dev/null || true)"
    before_started="$(snapshot_property "$unit" ActiveEnterTimestampMonotonic)"
    current_started="$(
      systemctl show "$unit" -p ActiveEnterTimestampMonotonic --value 2>/dev/null || true
    )"

    [[ "$active" == active ]] ||
      die "$unit is not active (observed ${active:-UNKNOWN})"
    [[ "$reload" == no ]] ||
      die "$unit has NeedDaemonReload=${reload:-UNKNOWN}"
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

  failed_units="$(systemctl --failed --no-legend --plain 2>/dev/null | sed '/^[[:space:]]*$/d' || true)"
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

assert_snapshot() {
  local snapshot_timestamp snapshot_epoch now_epoch snapshot_age
  local snapshot_commit current_commit current_status
  local -a expected_files observed_files guarded

  expected_files=(
    SHA256SUMS
    SNAPSHOT_COMPLETE
    context.txt
    manager-state.before.json
    protected-files.before.sha256
    registration.before.tsv
    root-registration-transaction.sh
    sanitized-health.before.txt
    services.before.txt
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

  grep -Fx "schema=1" "$snapshot/context.txt" >/dev/null ||
    die "snapshot schema is not supported"
  grep -Fx "purpose=system-manager-first-registration" "$snapshot/context.txt" >/dev/null ||
    die "snapshot purpose does not match"
  grep -Fx "host=sparkle-01" "$snapshot/context.txt" >/dev/null ||
    die "snapshot host does not match"
  grep -Fx "candidate=$candidate" "$snapshot/context.txt" >/dev/null ||
    die "snapshot candidate does not match the exact reviewed output"
  grep -Fx "transaction_sha256=$transaction_sha256" "$snapshot/context.txt" >/dev/null ||
    die "snapshot transaction checksum does not match the reviewed program"

  snapshot_timestamp="$(awk -F= '$1 == "timestamp_utc" { print $2; exit }' "$snapshot/context.txt")"
  snapshot_epoch="$(date -d "$snapshot_timestamp" +%s 2>/dev/null || true)"
  now_epoch="$(date +%s)"
  [[ -n "$snapshot_epoch" ]] || die "snapshot timestamp is missing or invalid"
  snapshot_age=$((now_epoch - snapshot_epoch))
  ((snapshot_age >= 0 && snapshot_age <= 1800)) ||
    die "snapshot is not in the current 30-minute registration window (age=${snapshot_age}s)"

  snapshot_commit="$(awk -F= '$1 == "repo_commit" { print $2; exit }' "$snapshot/context.txt")"
  current_commit="$(git -C "$repo_dir" rev-parse HEAD)"
  current_status="$(git -C "$repo_dir" status --porcelain --untracked-files=all)"
  [[ -n "$snapshot_commit" && "$current_commit" == "$snapshot_commit" ]] ||
    die "repository commit changed after the snapshot"
  [[ -z "$current_status" ]] ||
    die "repository must remain clean for the registration transaction"

  transaction="$snapshot/root-registration-transaction.sh"
  [[ "$(stat -c %u "$transaction")" == 0 && "$(stat -c %a "$transaction")" == 700 ]] ||
    die "snapshot transaction must be root-owned and mode 0700"
  [[ "$(sha256sum "$transaction" | awk '{print $1}')" == "$transaction_sha256" ]] ||
    die "snapshot transaction program checksum changed"
  bash -n "$transaction" || die "snapshot transaction failed its syntax check"

  mapfile -t guarded <"$snapshot/registration.before.tsv"
  [[ "${#guarded[@]}" -eq 6 ]] ||
    die "snapshot registration inventory must contain exactly six records"
  [[ "${guarded[0]}" == "ABSENT|$profile_dir" ]] ||
    die "snapshot did not record the profile directory absent"
  [[ "${guarded[1]}" == "ABSENT|$profile_path" ]] ||
    die "snapshot did not record the selected profile absent"
  [[ "${guarded[2]}" == "ABSENT|$generation_one_path" ]] ||
    die "snapshot did not record generation one absent"
  [[ "${guarded[3]}" == "ABSENT|$gcroot_path" ]] ||
    die "snapshot did not record the extra GC root absent"
  [[ "${guarded[4]}" == "EXACT_SYMLINK|$pilot_root|$candidate" ]] ||
    die "snapshot did not record exact pilot retention"
  [[ "${guarded[5]}" == "ACTIVE_RETAINED|$state_path" ]] ||
    die "snapshot did not record the exact active-unregistered state"

  cmp -s "$state_path" "$snapshot/manager-state.before.json" ||
    die "live activation state changed after the snapshot"
  sha256sum -c "$snapshot/protected-files.before.sha256" >/dev/null ||
    die "a protected file changed after the snapshot"

  pass snapshot "$snapshot is complete, private, checksum-valid, ${snapshot_age}s old, and bound to the exact candidate/transaction/pre-state"
}

assert_unregistered_active_state() {
  local state_class load_state

  [[ "$(hostname)" == sparkle-01 ]] ||
    die "this pilot is scoped to sparkle-01"
  [[ -L "$pilot_root" && "$(readlink -- "$pilot_root")" == "$candidate" ]] ||
    die "pilot root does not directly retain the exact candidate"
  [[ -f "$state_path" && ! -L "$state_path" ]] ||
    die "live manager state is missing or not a regular file"

  state_class="$("$repo_dir/scripts/audit-root-canary-state.sh" "$candidate" 2>/dev/null || true)"
  [[ "$state_class" == ACTIVE_RETAINED ]] ||
    die "expected ACTIVE_RETAINED pre-state; observed ${state_class:-UNKNOWN}"
  "$transaction" verify-absent "$candidate" >/dev/null ||
    die "transaction verifier rejected the unregistered pre-state"

  for unit in "$rollback_unit.timer" "$rollback_unit.service"; do
    load_state="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
    [[ -z "$load_state" || "$load_state" == not-found ]] ||
      die "rollback unit name is already loaded: $unit ($load_state)"
  done

  cmp -s "$state_path" "$snapshot/manager-state.before.json" ||
    die "live activation state differs from the snapshot"
  assert_protected_units
  assert_system_health
  assert_tailscale_health
  pass preflight "exact active canary is unregistered; boot linkage and broader ownership remain absent"
}

assert_registered_active_state() {
  local state_class

  "$transaction" verify-first "$candidate" >/dev/null ||
    die "transaction verifier rejected the first-generation registration"
  state_class="$(
    "$repo_dir/scripts/audit-root-canary-state.sh" \
      "$candidate" registered-first 2>/dev/null || true
  )"
  [[ "$state_class" == ACTIVE_REGISTERED_RETAINED ]] ||
    die "expected ACTIVE_REGISTERED_RETAINED state; observed ${state_class:-UNKNOWN}"

  cmp -s "$state_path" "$snapshot/manager-state.before.json" ||
    die "registration changed live activation state"
  sha256sum -c "$snapshot/protected-files.before.sha256" >/dev/null ||
    die "registration changed a protected account/Nix file"
  assert_protected_units
  assert_system_health
  assert_tailscale_health
  pass postregistration "generation one is registered while the exact live canary, pilot root, services, and no-boot boundary remain unchanged"
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

snapshot="$(readlink -f -- "$1")"
case "$snapshot" in
  "$repo_dir"/inventory/sparkle-01/raw/system-manager-registration/*)
    ;;
  *)
    die "snapshot must be below $repo_dir/inventory/sparkle-01/raw/system-manager-registration"
    ;;
esac
[[ -t 0 && -t 1 ]] ||
  die "run this guarded registration from an interactive terminal"

printf '# DGX System Manager first-registration pilot\n'
printf '# timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
info candidate "$candidate"
info registration "$profile_path;$generation_one_path;$gcroot_path"
info rollback "$rollback_unit.timer;10 minutes;exact registration-only rollback"
info unchanged "live activation;pilot root;boot linkage;all services"

assert_snapshot
assert_unregistered_active_state

systemd-run \
  --unit="$rollback_unit" \
  --description="Timed rollback for DGX System Manager first registration" \
  --collect \
  --service-type=exec \
  --on-active=10m \
  --timer-property=AccuracySec=1s \
  "$transaction" rollback-first "$candidate"
timer_armed=true

[[ "$(systemctl show "$rollback_unit.timer" -p ActiveState --value 2>/dev/null || true)" == active ]] ||
  die "rollback timer is not active"
[[ "$(systemctl show "$rollback_unit.timer" -p SubState --value 2>/dev/null || true)" == waiting ]] ||
  die "rollback timer is not waiting"
exec_start="$(systemctl show "$rollback_unit.service" -p ExecStart --value --no-pager)"
grep -F -- "$transaction" <<<"$exec_start" >/dev/null ||
  die "rollback service does not contain the exact snapshot transaction"
grep -F -- "rollback-first" <<<"$exec_start" >/dev/null ||
  die "rollback service does not select exact first-registration rollback"
grep -F -- "$candidate" <<<"$exec_start" >/dev/null ||
  die "rollback service does not contain the exact candidate"
pass rollback "timer is active/waiting and bound to exact registration-only rollback"
info rollback_schedule "$(
  systemctl list-timers --all --no-legend --no-pager "$rollback_unit.timer" |
    sed 's/^[[:space:]]*//; s/[[:space:]][[:space:]]*/ /g'
)"

registration_started=true
"$transaction" apply-first "$candidate"
assert_registered_active_state

printf '\n%s\n' \
  'Automatic postflight passed. Verify the physical keyboard/display/local terminal still works.' \
  'Keep this terminal alive too. Within five minutes, type exactly KEEP REGISTRATION.' \
  'Any other input, Ctrl-C, disconnect, or timeout leaves the ten-minute registration-only rollback armed.' \
  "Immediate manual rollback is: $transaction rollback-first $candidate" \
  'Rollback removes the new profile/generation-one/extra-root surface only; it leaves the live canary and pilot root intact.'
printf '> '

console_reply=
if ! read -r -t 300 console_reply; then
  die "local-console confirmation timed out; leaving registration rollback armed"
fi
[[ "$console_reply" == "KEEP REGISTRATION" ]] ||
  die "confirmation did not match; leaving registration rollback armed"

assert_registered_active_state
systemctl stop "$rollback_unit.timer"
timer_armed=false

timer_state="$(systemctl show "$rollback_unit.timer" -p ActiveState --value 2>/dev/null || true)"
[[ -z "$timer_state" || "$timer_state" == inactive ]] ||
  die "rollback timer did not become inactive after confirmed postflight"

"$transaction" verify-first "$candidate" >/dev/null ||
  die "registration changed while disarming rollback"
[[ -L "$pilot_root" && "$(readlink -- "$pilot_root")" == "$candidate" ]] ||
  die "pilot root changed while disarming rollback"

pass registration "first generation retained after repeated automatic postflight and independent local-console confirmation"
printf '%s\n' \
  "KEEP: $pilot_root remains required while the canary is active." \
  "REGISTERED: $profile_path and $gcroot_path point to the exact current canary." \
  "NOT DONE: no activation, reactivation, boot linkage, service restart, broader root role, desktop switch, or Tailscale migration occurred."
