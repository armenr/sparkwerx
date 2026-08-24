#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
candidate=/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager
pilot_root=/nix/var/nix/gcroots/dgx-setup-root-canary-pilot
rollback_unit=dgx-root-canary-rollback
nix_store_bin=/nix/var/nix/profiles/default/bin/nix-store

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

guarded_paths=(
  "${managed_paths[@]}"
  /var/lib/system-manager/state/system-manager-state.json
  /nix/var/nix/profiles/system-manager-profiles/system-manager
  /nix/var/nix/gcroots/system-manager-current
  "$pilot_root"
)

protected_absent_paths=(
  /etc/profile.d/system-manager-path.sh
  /etc/environment.d/10-system-manager.conf
  /etc/systemd/system/default.target.wants/system-manager.target
  /etc/systemd/system/system-manager-path.service
  /etc/systemd/system/userborn.service
  /run/wrappers
  /run/current-system
)

timer_armed=false
activation_started=false
pilot_root_created=false

usage() {
  printf 'Usage: sudo %s /absolute/private/snapshot-directory\n' "$(basename "$0")" >&2
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
        "ROLLBACK ARMED: do not remove $pilot_root; $rollback_unit.timer will run the exact deactivation program." \
        >&2
    elif [[ "$activation_started" == true ]]; then
      printf '%s\n' \
        "WARNING: activation started but the rollback timer is not known to be armed; run $candidate/bin/deactivate from the console." \
        >&2
    elif [[ "$pilot_root_created" == true ]]; then
      printf '%s\n' \
        "No activation started. The exact pilot GC root was created and deliberately left for explicit review." \
        >&2
    fi
  fi
}
trap on_exit EXIT

require_commands() {
  local command_name

  for command_name in \
    awk diff grep hostname jq nvidia-smi readlink sed sha256sum stat \
    systemctl systemd-run tailscale timeout; do
    command -v "$command_name" >/dev/null 2>&1 || \
      die "required command is unavailable: $command_name"
  done
}

assert_path_absent() {
  local path="$1"

  if [[ -e "$path" || -L "$path" ]]; then
    die "collision or forbidden path exists: $path"
  fi
}

snapshot_fragment_path() {
  local unit="$1"

  awk -F= -v wanted="$unit" '
    $1 == "Id" { selected = ($2 == wanted) }
    selected && $1 == "FragmentPath" {
      sub(/^FragmentPath=/, "")
      print
      exit
    }
  ' "$snapshot/services.before.txt"
}

assert_protected_units() {
  local unit active reload before_fragment current_fragment

  for unit in "${protected_units[@]}"; do
    active="$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)"
    reload="$(systemctl show "$unit" -p NeedDaemonReload --value 2>/dev/null || true)"
    before_fragment="$(snapshot_fragment_path "$unit")"
    current_fragment="$(systemctl show "$unit" -p FragmentPath --value 2>/dev/null || true)"

    [[ "$active" == active ]] || \
      die "$unit is not active (observed ${active:-UNKNOWN})"
    [[ "$reload" == no ]] || \
      die "$unit has NeedDaemonReload=${reload:-UNKNOWN}"
    [[ -n "$before_fragment" && "$current_fragment" == "$before_fragment" ]] || \
      die "$unit changed FragmentPath (before ${before_fragment:-UNKNOWN}; now ${current_fragment:-UNKNOWN})"
  done

  pass protected_units "all seven factory/access services remain active, loaded from their original fragments, with no pending reload"
}

assert_system_health() {
  local system_state failed_units gpu_state

  system_state="$(systemctl is-system-running 2>/dev/null || true)"
  [[ "$system_state" == running ]] || \
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

  jq -e . >/dev/null 2>&1 <<<"$status_json" || \
    die "Tailscale status did not return valid JSON"
  jq -e . >/dev/null 2>&1 <<<"$prefs_json" || \
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
    "$want_running" == true && "$run_ssh" == true ]] || \
    die "Tailscale health failed: backend=$backend;online=$online;WantRunning=$want_running;RunSSH=$run_ssh"

  pass tailscale "backend=$backend;online=$online;WantRunning=$want_running;RunSSH=$run_ssh"
}

assert_snapshot() {
  local expected_absent

  [[ -f "$snapshot/SNAPSHOT_COMPLETE" ]] || \
    die "snapshot completion marker is missing"
  [[ ! -e "$snapshot/SNAPSHOT_INCOMPLETE" ]] || \
    die "snapshot has an incomplete marker"
  [[ "$(<"$snapshot/SNAPSHOT_COMPLETE")" == "Snapshot creation completed." ]] || \
    die "snapshot completion marker is invalid"
  [[ "$(stat -c %u "$snapshot")" == 0 && "$(stat -c %a "$snapshot")" == 700 ]] || \
    die "snapshot must be root-owned and mode 0700"

  (
    cd "$snapshot"
    sha256sum -c SHA256SUMS >/dev/null
  ) || die "snapshot checksum verification failed"

  grep -Fx "host=sparkle-01" "$snapshot/context.txt" >/dev/null || \
    die "snapshot host does not match sparkle-01"
  grep -Fx "candidate=$candidate" "$snapshot/context.txt" >/dev/null || \
    die "snapshot candidate does not match the exact reviewed output"

  expected_absent="$(printf 'ABSENT|%s\n' "${guarded_paths[@]}")"
  diff -u <(printf '%s\n' "$expected_absent") "$snapshot/guarded-paths.before.tsv" >/dev/null || \
    die "snapshot guarded-path inventory is not the exact expected set"

  sha256sum -c "$snapshot/protected-files.before.sha256" >/dev/null || \
    die "protected files already differ from the snapshot"

  pass snapshot "$snapshot is complete, private, checksum-valid, and bound to the exact candidate"
}

assert_preactivation_state() {
  local path load_state

  [[ "$(hostname)" == sparkle-01 ]] || \
    die "this pilot is scoped to sparkle-01, not $(hostname)"
  "$nix_store_bin" --check-validity "$candidate" >/dev/null 2>&1 || \
    die "exact candidate is not valid in the local Nix store"
  [[ -x "$candidate/bin/activate" && -x "$candidate/bin/deactivate" ]] || \
    die "exact candidate lacks activation or deactivation"

  for path in "${guarded_paths[@]}" "${protected_absent_paths[@]}"; do
    assert_path_absent "$path"
  done

  for unit in "$rollback_unit.timer" "$rollback_unit.service"; do
    load_state="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
    [[ -z "$load_state" || "$load_state" == not-found ]] || \
      die "rollback unit name is already loaded: $unit ($load_state)"
  done

  "$candidate/bin/preActivationAssertions" >/dev/null
  assert_protected_units
  assert_system_health
  assert_tailscale_health
  pass preactivation "all exact collisions are absent and the candidate assertion passes"
}

assert_symlink_target() {
  local path="$1"
  local expected="$2"
  local observed expected_resolved

  [[ -L "$path" ]] || die "expected managed symlink is missing: $path"
  observed="$(readlink -f -- "$path")"
  expected_resolved="$(readlink -f -- "$expected")"
  [[ -n "$observed" && "$observed" == "$expected_resolved" ]] || \
    die "managed symlink payload mismatch at $path (expected $expected_resolved; observed ${observed:-UNKNOWN})"
}

assert_postactivation_state() {
  local canary_source service_source sysinit_source manager_source path

  canary_source="$(jq -r '.entries["dgx-setup/canary"].source' "$candidate/etcFiles/etcFiles.json")"
  service_source="$(jq -r '.["dgx-setup-canary.service"].storePath' "$candidate/services/services.json")"
  sysinit_source="$(jq -r '.["sysinit-reactivation.target"].storePath' "$candidate/services/services.json")"
  manager_source="$(jq -r '.["system-manager.target"].storePath' "$candidate/services/services.json")"

  assert_symlink_target /etc/dgx-setup/canary "$canary_source/dgx-setup/canary"
  assert_symlink_target /etc/systemd/system/dgx-setup-canary.service "$service_source"
  assert_symlink_target /etc/systemd/system/sysinit-reactivation.target "$sysinit_source"
  assert_symlink_target /etc/systemd/system/system-manager.target "$manager_source"

  path=/etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service
  [[ -L "$path" ]] || die "expected managed dependency symlink is missing: $path"
  [[ "$(readlink -f -- "$path")" == "$(readlink -f -- /etc/systemd/system/dgx-setup-canary.service)" ]] || \
    die "managed dependency symlink does not resolve to the canary service"

  grep -Fx "host=sparkle-01" /etc/dgx-setup/canary >/dev/null || \
    die "canary content does not identify sparkle-01"

  jq -e '
    ((keys | sort) == ["fileTree", "services", "version"]) and
    (.version == 1) and
    ((.fileTree | keys | sort) == ["backedUpFiles", "files"]) and
    ((.fileTree.files | sort) == [
      "/etc/dgx-setup/canary",
      "/etc/systemd/system/dgx-setup-canary.service",
      "/etc/systemd/system/sysinit-reactivation.target",
      "/etc/systemd/system/system-manager.target",
      "/etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service"
    ]) and
    (.fileTree.backedUpFiles == []) and
    ((.services | keys | sort) == [
      "dgx-setup-canary.service",
      "sysinit-reactivation.target",
      "system-manager.target"
    ])
  ' /var/lib/system-manager/state/system-manager-state.json >/dev/null || \
    die "System Manager state exceeds or differs from the exact canary allowlist"

  for path in "${protected_absent_paths[@]}"; do
    assert_path_absent "$path"
  done
  assert_path_absent /nix/var/nix/profiles/system-manager-profiles/system-manager
  assert_path_absent /nix/var/nix/gcroots/system-manager-current

  [[ -L "$pilot_root" && "$(readlink -- "$pilot_root")" == "$candidate" ]] || \
    die "pilot GC root is missing or no longer points to the exact candidate"
  sha256sum -c "$snapshot/protected-files.before.sha256" >/dev/null || \
    die "a protected account/Nix file changed during activation"

  [[ "$(systemctl show dgx-setup-canary.service -p ActiveState --value 2>/dev/null || true)" == active ]] || \
    die "dgx-setup-canary.service is not active"
  [[ "$(systemctl show dgx-setup-canary.service -p NeedDaemonReload --value 2>/dev/null || true)" == no ]] || \
    die "dgx-setup-canary.service has a pending daemon reload"
  [[ "$(systemctl show system-manager.target -p ActiveState --value 2>/dev/null || true)" == active ]] || \
    die "system-manager.target is not active"

  assert_protected_units
  assert_system_health
  assert_tailscale_health
  pass postactivation "exact five-path/three-service canary is active; registration remains absent"
}

if [[ "$EUID" -ne 0 ]]; then
  die "run this helper with sudo"
fi

if [[ "$#" -ne 1 ]]; then
  usage
  exit 2
fi

PATH="/nix/var/nix/profiles/default/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export PATH
require_commands

snapshot="$(readlink -f -- "$1")"
case "$snapshot" in
  "$repo_dir"/inventory/sparkle-01/raw/system-manager-canary/*)
    ;;
  *)
    die "snapshot must be below $repo_dir/inventory/sparkle-01/raw/system-manager-canary"
    ;;
esac

[[ -t 0 && -t 1 ]] || \
  die "run this guarded activation from an interactive terminal"

printf '# DGX System Manager root-canary pilot\n'
printf '# timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
info candidate "$candidate"
info pilot_root "$pilot_root"
info rollback "$rollback_unit.timer;10 minutes;exact candidate deactivate"

assert_snapshot
assert_preactivation_state

ln -s -- "$candidate" "$pilot_root"
pilot_root_created=true
[[ "$(readlink -- "$pilot_root")" == "$candidate" ]] || \
  die "pilot GC root target verification failed"
pass pilot_root "$pilot_root -> $candidate"

systemd-run \
  --unit="$rollback_unit" \
  --description="Timed rollback for DGX System Manager canary" \
  --collect \
  --service-type=exec \
  --on-active=10m \
  --timer-property=AccuracySec=1s \
  "$candidate/bin/deactivate"
timer_armed=true

[[ "$(systemctl show "$rollback_unit.timer" -p ActiveState --value 2>/dev/null || true)" == active ]] || \
  die "rollback timer is not active"
[[ "$(systemctl show "$rollback_unit.timer" -p SubState --value 2>/dev/null || true)" == waiting ]] || \
  die "rollback timer is not waiting"
systemctl show "$rollback_unit.service" -p ExecStart --value --no-pager | \
  grep -F -- "$candidate/bin/deactivate" >/dev/null || \
  die "rollback service does not contain the exact deactivation path"
pass rollback "timer is active/waiting and bound to the exact deactivation program"
info rollback_schedule "$(
  systemctl list-timers --all --no-legend --no-pager "$rollback_unit.timer" |
    sed 's/^[[:space:]]*//; s/[[:space:]][[:space:]]*/ /g'
)"

activation_started=true
"$candidate/bin/activate"
assert_postactivation_state

printf '\n%s\n' \
  'Automatic postflight passed. Now verify that the physical keyboard/display/local terminal works.' \
  'Keep this terminal alive too. Within five minutes, type exactly KEEP CANARY to retain the activation.' \
  "Any other input, Ctrl-C, disconnect, or timeout leaves the ten-minute rollback armed." \
  "Immediate manual rollback from the console is: $candidate/bin/deactivate"
printf '> '

console_reply=
if ! read -r -t 300 console_reply; then
  die "local-console confirmation timed out; leaving rollback armed"
fi
[[ "$console_reply" == "KEEP CANARY" ]] || \
  die "confirmation did not match; leaving rollback armed"

assert_postactivation_state
systemctl stop "$rollback_unit.timer"
timer_armed=false

timer_state="$(systemctl show "$rollback_unit.timer" -p ActiveState --value 2>/dev/null || true)"
[[ -z "$timer_state" || "$timer_state" == inactive ]] || \
  die "rollback timer did not become inactive after confirmed postflight"

[[ -L "$pilot_root" && "$(readlink -- "$pilot_root")" == "$candidate" ]] || \
  die "pilot GC root changed while disarming rollback"
[[ "$(systemctl show dgx-setup-canary.service -p ActiveState --value 2>/dev/null || true)" == active ]] || \
  die "canary stopped unexpectedly while disarming rollback"

pass activation "host canary retained after automatic postflight and independent local-console confirmation"
printf '%s\n' \
  "KEEP: $pilot_root must remain until separately authorized, verified deactivation." \
  "NOT DONE: no System Manager profile was registered and no broader root role was activated."
