#!/usr/bin/env bash
set -uo pipefail

# Persistent first-reboot recovery for the exact retained sparkle-01 System
# Manager generation-three canary. The Nix-built wrapper supplies the exact
# bundle, generation candidates, and reviewed boot rollback transaction.
#
# arm installs a temporary root-owned recovery surface and enables, but never
# starts, its timer. The next boot starts that timer through timers.target. If
# confirmation does not disarm it, rollback restores exact no-boot generation
# two. All destructive paths are exact symlinks; foreign collisions fail
# closed and are never replaced.

service_unit=dgx-root-reboot-recovery.service
timer_unit=dgx-root-reboot-recovery.timer
unit_dir=/etc/systemd/system
service_path=$unit_dir/$service_unit
timer_path=$unit_dir/$timer_unit
wants_dir=$unit_dir/timers.target.wants
wants_path=$wants_dir/$timer_unit
state_parent=/var/lib/dgx-setup
state_dir=$state_parent/reboot-recovery
state_path=$state_dir/state
recovery_root=/nix/var/nix/gcroots/dgx-setup-root-canary-reboot-recovery-pilot
lock_path=/run/lock/dgx-root-reboot-recovery.lock
confirmation_phrase='KEEP REBOOTED GENERATION THREE'
cleanup_phrase='CLEAN ROLLED BACK REBOOT RECOVERY'

required_environment=(
  DGX_RECOVERY_BUNDLE
  DGX_RECOVERY_GENERATION_ONE
  DGX_RECOVERY_GENERATION_TWO
  DGX_RECOVERY_GENERATION_THREE
  DGX_RECOVERY_BOOT_TRANSACTION
  DGX_RECOVERY_AUDIT
)

for variable in "${required_environment[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    printf 'FAIL|required environment variable is absent: %s\n' "$variable" >&2
    exit 1
  fi
done

bundle=$DGX_RECOVERY_BUNDLE
generation_one=$DGX_RECOVERY_GENERATION_ONE
generation_two=$DGX_RECOVERY_GENERATION_TWO
generation_three=$DGX_RECOVERY_GENERATION_THREE
boot_transaction=$DGX_RECOVERY_BOOT_TRANSACTION
audit_program=$DGX_RECOVERY_AUDIT
bundle_program=$bundle/bin/dgx-root-reboot-recovery
bundle_service=$bundle/lib/systemd/system/$service_unit
bundle_timer=$bundle/lib/systemd/system/$timer_unit

PATH=${DGX_RECOVERY_PATH:-/nix/var/nix/profiles/default/bin:/usr/sbin:/usr/bin:/sbin:/bin}
NIX_USER_CONF_FILES=/dev/null
export PATH NIX_USER_CONF_FILES

usage() {
  printf '%s\n' \
    "Usage: dgx-root-reboot-recovery arm|verify-armed-preboot|disarm-preboot|verify-armed-postboot|rollback|verify-rolled-back" \
    "       dgx-root-reboot-recovery confirm '$confirmation_phrase'" \
    "       dgx-root-reboot-recovery cleanup-rolled-back '$cleanup_phrase'" >&2
}

info() {
  printf 'INFO|%s|%s\n' "$1" "$2"
}

pass() {
  printf 'PASS|%s|%s\n' "$1" "$2"
}

fail() {
  printf 'FAIL|%s\n' "$1" >&2
  return 1
}

path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

current_boot_id() {
  local observed

  [[ -r /proc/sys/kernel/random/boot_id ]] ||
    fail 'kernel boot ID is unreadable' || return 1
  observed="$(tr -d '\n' </proc/sys/kernel/random/boot_id)"
  [[ "$observed" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] ||
    fail 'kernel boot ID is malformed' || return 1
  printf '%s\n' "$observed"
}

validate_compiled_inputs() {
  local candidate

  [[ "$bundle" =~ ^/nix/store/[a-z0-9]{32}-dgx-root-reboot-recovery(-test)?$ &&
    -d "$bundle" && -x "$bundle_program" ]] ||
    fail "recovery bundle is missing or malformed: $bundle" || return 1
  [[ -f "$bundle_service" && -f "$bundle_timer" ]] ||
    fail 'recovery bundle lacks its exact systemd unit pair' || return 1
  [[ "$boot_transaction" =~ ^/nix/store/[a-z0-9]{32}-root-boot-persistence-transaction\.sh$ &&
    -r "$boot_transaction" ]] ||
    fail 'reviewed boot rollback transaction is missing or malformed' || return 1
  [[ "$audit_program" =~ ^/nix/store/[a-z0-9]{32}-audit-root-canary-state\.sh$ &&
    -r "$audit_program" ]] ||
    fail 'reviewed root-manager state auditor is missing or malformed' || return 1

  for candidate in "$generation_one" "$generation_two" "$generation_three"; do
    [[ "$candidate" =~ ^/nix/store/[a-z0-9]{32}-system-manager$ &&
      -d "$candidate" ]] ||
      fail "System Manager candidate is missing or malformed: $candidate" ||
      return 1
  done
  [[ "$generation_one" != "$generation_two" &&
    "$generation_one" != "$generation_three" &&
    "$generation_two" != "$generation_three" ]] ||
    fail 'System Manager candidates are not three distinct outputs' || return 1

  grep -Fx "ExecStart=$bundle_program rollback" "$bundle_service" >/dev/null ||
    fail 'recovery service does not execute the exact bundle rollback action' ||
    return 1
  grep -Fx "Unit=$service_unit" "$bundle_timer" >/dev/null ||
    fail 'recovery timer does not target the exact recovery service' || return 1
  grep -Fx 'WantedBy=timers.target' "$bundle_timer" >/dev/null ||
    fail 'recovery timer is not installable through timers.target' || return 1
}

run_boot_transaction() {
  local action="$1"

  bash "$boot_transaction" "$action" \
    "$generation_one" "$generation_two" "$generation_three"
}

verify_generation_three_postboot() {
  local recovery_expectation="$1"
  local observed

  observed="$(
    bash "$audit_program" \
      "$generation_three" registered-third-boot \
      "$generation_one" "$generation_two" \
      postboot "$recovery_expectation"
  )" || {
    fail 'post-boot generation-three state audit failed'
    return 1
  }
  [[ "$observed" == ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_REBOOTED_RETAINED ]] ||
    fail "post-boot generation-three classifier returned: ${observed:-UNKNOWN}" ||
    return 1
}

state_content() {
  local status="$1"
  local arming_boot_id="$2"
  local completion_boot_id="${3:-}"

  printf 'schema=1\n'
  printf 'host=sparkle-01\n'
  printf 'purpose=system-manager generation-three first-reboot recovery\n'
  printf 'status=%s\n' "$status"
  printf 'arming_boot_id=%s\n' "$arming_boot_id"
  if [[ -n "$completion_boot_id" ]]; then
    printf 'completion_boot_id=%s\n' "$completion_boot_id"
  fi
  printf 'generation_one=%s\n' "$generation_one"
  printf 'generation_two=%s\n' "$generation_two"
  printf 'generation_three=%s\n' "$generation_three"
  printf 'bundle=%s\n' "$bundle"
  printf 'rollback=exact registered and active no-boot generation two\n'
}

state_field() {
  local field="$1"
  local observed count

  [[ -r "$state_path" ]] ||
    fail "recovery state is unreadable: $state_path" || return 1
  observed="$(sed -n "s/^${field}=//p" "$state_path")"
  count="$(grep -c "^${field}=" "$state_path" || true)"
  [[ "$count" == 1 && -n "$observed" ]] ||
    fail "recovery state has no unique $field field" || return 1
  printf '%s\n' "$observed"
}

assert_state() {
  local expected_status="$1"
  local arming_boot_id completion_boot_id=''

  [[ -d "$state_dir" && ! -L "$state_dir" ]] ||
    fail 'recovery state directory is absent or not a real directory' || return 1
  [[ "$(stat -c %u:%g:%a -- "$state_dir" 2>/dev/null || true)" == 0:0:700 ]] ||
    fail 'recovery state directory is not root:root mode 0700' || return 1
  [[ -f "$state_path" && ! -L "$state_path" ]] ||
    fail 'recovery state is absent or not a regular file' || return 1
  [[ "$(stat -c %u:%g:%a -- "$state_path" 2>/dev/null || true)" == 0:0:600 ]] ||
    fail 'recovery state is not root:root mode 0600' || return 1

  arming_boot_id="$(state_field arming_boot_id)" || return 1
  [[ "$arming_boot_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] ||
    fail 'recorded arming boot ID is malformed' || return 1
  if [[ "$expected_status" == rolled-back ]]; then
    completion_boot_id="$(state_field completion_boot_id)" || return 1
    [[ "$completion_boot_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ &&
      "$completion_boot_id" != "$arming_boot_id" ]] ||
      fail 'recorded rollback boot ID is malformed or unchanged' || return 1
  fi

  cmp -s "$state_path" \
    <(state_content "$expected_status" "$arming_boot_id" "$completion_boot_id") ||
    fail "recovery state differs from exact $expected_status schema" || return 1
}

write_state() {
  local status="$1"
  local arming_boot_id="$2"
  local completion_boot_id="${3:-}"
  local temporary=$state_dir/.state.dgx-$$

  umask 077
  if ! state_content "$status" "$arming_boot_id" "$completion_boot_id" >"$temporary"; then
    unlink -- "$temporary" 2>/dev/null || true
    fail 'could not write temporary recovery state'
    return 1
  fi
  if ! chown 0:0 "$temporary" ||
    ! chmod 0600 "$temporary" ||
    ! mv -Tf -- "$temporary" "$state_path"; then
    unlink -- "$temporary" 2>/dev/null || true
    fail 'could not atomically install exact recovery state'
    return 1
  fi
  assert_state "$status"
}

assert_unit_links() {
  [[ -L "$service_path" && "$(readlink -- "$service_path")" == "$bundle_service" ]] ||
    fail 'installed recovery service is not the exact bundle symlink' || return 1
  [[ -L "$timer_path" && "$(readlink -- "$timer_path")" == "$bundle_timer" ]] ||
    fail 'installed recovery timer is not the exact bundle symlink' || return 1
  [[ "$(systemctl show "$service_unit" -p LoadState --value 2>/dev/null || true)" == loaded ]] ||
    fail 'installed recovery service is not loaded' || return 1
  [[ "$(systemctl show "$timer_unit" -p LoadState --value 2>/dev/null || true)" == loaded ]] ||
    fail 'installed recovery timer is not loaded' || return 1
  [[ "$(systemctl show "$service_unit" -p NeedDaemonReload --value 2>/dev/null || true)" == no ]] ||
    fail 'recovery service has a pending daemon reload' || return 1
  [[ "$(systemctl show "$timer_unit" -p NeedDaemonReload --value 2>/dev/null || true)" == no ]] ||
    fail 'recovery timer has a pending daemon reload' || return 1
}

assert_enabled_link() {
  [[ -L "$wants_path" && "$(readlink -- "$wants_path")" == ../$timer_unit ]] ||
    fail 'recovery timer enablement link is absent or inexact' || return 1
  [[ "$(systemctl is-enabled "$timer_unit" 2>/dev/null || true)" == enabled ]] ||
    fail 'recovery timer is not persistently enabled' || return 1
}

assert_installed_surface() {
  local expected_status="$1"

  [[ -L "$recovery_root" && "$(readlink -- "$recovery_root")" == "$bundle" ]] ||
    fail 'recovery GC root is absent or does not retain the exact bundle' || return 1
  assert_state "$expected_status" || return 1
  assert_unit_links || return 1
  if [[ "$expected_status" == armed ]]; then
    assert_enabled_link || return 1
  elif path_exists "$wants_path"; then
    fail 'rolled-back recovery timer remains enabled'
    return 1
  fi
}

assert_surface_absent() {
  local path load_state

  for path in \
    "$recovery_root" "$state_dir" "$service_path" "$timer_path" "$wants_path"; do
    if path_exists "$path"; then
      fail "unexpected reboot-recovery path exists: $path"
      return 1
    fi
  done
  for unit in "$service_unit" "$timer_unit"; do
    load_state="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
    [[ -z "$load_state" || "$load_state" == not-found ]] ||
      fail "unexpected reboot-recovery unit remains loaded: $unit ($load_state)" ||
      return 1
  done
}

assert_same_boot() {
  local arming_boot_id current

  arming_boot_id="$(state_field arming_boot_id)" || return 1
  current="$(current_boot_id)" || return 1
  [[ "$current" == "$arming_boot_id" ]] ||
    fail 'operation requires the original pre-reboot boot ID' || return 1
}

assert_new_boot() {
  local arming_boot_id current

  arming_boot_id="$(state_field arming_boot_id)" || return 1
  current="$(current_boot_id)" || return 1
  [[ "$current" != "$arming_boot_id" ]] ||
    fail 'recovery refuses to act before the kernel boot ID changes' || return 1
}

acquire_lock() {
  install -d -m 0755 -o 0 -g 0 /run/lock || return 1
  exec 9>"$lock_path" ||
    fail 'could not open the reboot-recovery lock' || return 1
  flock -n 9 ||
    fail 'another reboot-recovery action holds the exact lock' || return 1
}

validate_injection() {
  local stage="${DGX_RECOVERY_TEST_FAIL_STAGE:-}"

  [[ -n "$stage" ]] || return 0
  case "$stage" in
    after-root | after-state | after-units)
      ;;
    *)
      fail "unknown disposable recovery injection: $stage"
      return 1
      ;;
  esac
  [[ -r /run/systemd/container &&
    "$(< /run/systemd/container)" == systemd-nspawn ]] ||
    fail 'recovery failure injection is allowed only in systemd-nspawn' ||
    return 1
}

arm_created_root=false
arm_created_state_parent=false
arm_created_state_dir=false
arm_created_service=false
arm_created_timer=false
arm_created_wants_dir=false
arm_created_wants=false

cleanup_partial_arm() {
  if [[ "$arm_created_wants" == true ]] &&
    [[ -L "$wants_path" && "$(readlink -- "$wants_path")" == ../$timer_unit ]]; then
    unlink -- "$wants_path" || true
  fi
  if [[ "$arm_created_timer" == true ]] &&
    [[ -L "$timer_path" && "$(readlink -- "$timer_path")" == "$bundle_timer" ]]; then
    unlink -- "$timer_path" || true
  fi
  if [[ "$arm_created_service" == true ]] &&
    [[ -L "$service_path" && "$(readlink -- "$service_path")" == "$bundle_service" ]]; then
    unlink -- "$service_path" || true
  fi
  if [[ "$arm_created_state_dir" == true && -d "$state_dir" && ! -L "$state_dir" ]]; then
    unlink -- "$state_path" 2>/dev/null || true
    rmdir -- "$state_dir" 2>/dev/null || true
  fi
  if [[ "$arm_created_wants_dir" == true && -d "$wants_dir" && ! -L "$wants_dir" ]]; then
    rmdir -- "$wants_dir" 2>/dev/null || true
  fi
  if [[ "$arm_created_state_parent" == true && -d "$state_parent" && ! -L "$state_parent" ]]; then
    rmdir -- "$state_parent" 2>/dev/null || true
  fi
  if [[ "$arm_created_root" == true ]] &&
    [[ -L "$recovery_root" && "$(readlink -- "$recovery_root")" == "$bundle" ]]; then
    unlink -- "$recovery_root" || true
  fi
  systemctl daemon-reload >/dev/null 2>&1 || true
}

arm_impl() {
  local boot_id temporary_root=$recovery_root.dgx-arm-$$

  validate_injection || return 1
  run_boot_transaction verify-after ||
    fail 'host is not exact registered/live boot-linked generation three' ||
    return 1
  assert_surface_absent || return 1
  boot_id="$(current_boot_id)" || return 1

  if path_exists "$temporary_root"; then
    fail "temporary recovery root collision exists: $temporary_root"
    return 1
  fi
  ln -s -- "$bundle" "$temporary_root" ||
    fail 'could not create temporary recovery GC root' || return 1
  mv -Tf -- "$temporary_root" "$recovery_root" || {
    unlink -- "$temporary_root" 2>/dev/null || true
    fail 'could not atomically install recovery GC root'
    return 1
  }
  arm_created_root=true
  if [[ "${DGX_RECOVERY_TEST_FAIL_STAGE:-}" == after-root ]]; then
    fail 'disposable failure injected after recovery-root creation'
    return 1
  fi

  if [[ ! -d "$state_parent" ]]; then
    install -d -m 0700 -o 0 -g 0 "$state_parent" || return 1
    arm_created_state_parent=true
  fi
  [[ -d "$state_parent" && ! -L "$state_parent" ]] ||
    fail 'recovery state parent is not a real directory' || return 1
  [[ "$(stat -c %u:%g:%a -- "$state_parent" 2>/dev/null || true)" == 0:0:700 ]] ||
    fail 'existing recovery state parent is not root:root mode 0700' || return 1
  install -d -m 0700 -o 0 -g 0 "$state_dir" || return 1
  arm_created_state_dir=true
  write_state armed "$boot_id" || return 1
  if [[ "${DGX_RECOVERY_TEST_FAIL_STAGE:-}" == after-state ]]; then
    fail 'disposable failure injected after recovery-state creation'
    return 1
  fi

  ln -s -- "$bundle_service" "$service_path" || return 1
  arm_created_service=true
  ln -s -- "$bundle_timer" "$timer_path" || return 1
  arm_created_timer=true
  if [[ "${DGX_RECOVERY_TEST_FAIL_STAGE:-}" == after-units ]]; then
    fail 'disposable failure injected after recovery-unit installation'
    return 1
  fi

  if [[ ! -d "$wants_dir" ]]; then
    install -d -m 0755 -o 0 -g 0 "$wants_dir" || return 1
    arm_created_wants_dir=true
  fi
  [[ -d "$wants_dir" && ! -L "$wants_dir" ]] ||
    fail 'timers.target wants path is not a real directory' || return 1
  ln -s -- ../$timer_unit "$wants_path" || return 1
  arm_created_wants=true

  systemctl daemon-reload ||
    fail 'systemd daemon reload failed while arming recovery' || return 1
  assert_installed_surface armed || return 1
  [[ "$(systemctl show "$timer_unit" -p ActiveState --value 2>/dev/null || true)" == inactive ]] ||
    fail 'recovery timer unexpectedly started in the pre-reboot boot' || return 1
  [[ "$(systemctl show "$service_unit" -p ActiveState --value 2>/dev/null || true)" == inactive ]] ||
    fail 'recovery service unexpectedly started while arming' || return 1
  assert_same_boot || return 1
  run_boot_transaction verify-after || return 1
}

arm_recovery() {
  acquire_lock || return 1
  arm_impl || {
    local status=$?
    cleanup_partial_arm
    return "$status"
  }
  pass recovery_armed 'persistent timer is enabled but inactive until the next boot'
}

verify_armed_preboot() {
  assert_installed_surface armed || return 1
  assert_same_boot || return 1
  run_boot_transaction verify-after || return 1
  [[ "$(systemctl show "$timer_unit" -p ActiveState --value 2>/dev/null || true)" == inactive ]] ||
    fail 'pre-reboot recovery timer is not inactive' || return 1
  [[ "$(systemctl show "$service_unit" -p ActiveState --value 2>/dev/null || true)" == inactive ]] ||
    fail 'pre-reboot recovery service is not inactive' || return 1
  pass recovery_preboot 'exact recovery is enabled for next boot and has not started on this boot'
}

disarm_preboot() {
  acquire_lock || return 1
  assert_installed_surface armed || return 1
  assert_same_boot || return 1
  run_boot_transaction verify-after || return 1
  remove_exact_recovery_surface armed || return 1
  run_boot_transaction verify-after || return 1
  pass recovery_disarmed 'same-boot recovery arming canceled; generation three remains exact'
}

verify_armed_postboot() {
  local next

  assert_installed_surface armed || return 1
  assert_new_boot || return 1
  verify_generation_three_postboot verified-by-caller || return 1
  [[ "$(systemctl show "$timer_unit" -p ActiveState --value 2>/dev/null || true)" == active ]] ||
    fail 'post-boot recovery timer is not active' || return 1
  [[ "$(systemctl show "$timer_unit" -p SubState --value 2>/dev/null || true)" == waiting ]] ||
    fail 'post-boot recovery timer is not waiting' || return 1
  [[ "$(systemctl show "$service_unit" -p ActiveState --value 2>/dev/null || true)" == inactive ]] ||
    fail 'recovery service has already started' || return 1
  next="$(systemctl show "$timer_unit" -p NextElapseUSecMonotonic --value 2>/dev/null || true)"
  [[ -n "$next" && "$next" != n/a && "$next" != 0 ]] ||
    fail 'post-boot recovery timer has no monotonic deadline' || return 1
  pass recovery_postboot 'generation three booted and exact persistent rollback is active/waiting'
}

disable_timer_link() {
  if path_exists "$wants_path"; then
    [[ -L "$wants_path" && "$(readlink -- "$wants_path")" == ../$timer_unit ]] ||
      fail 'refusing to remove an unknown recovery enablement path' || return 1
    unlink -- "$wants_path" ||
      fail 'could not disable the persistent recovery timer' || return 1
  fi
}

rollback_recovery() {
  local arming_boot_id completion_boot_id status

  acquire_lock || return 1
  status="$(state_field status)" || return 1
  case "$status" in
    armed | rolled-back)
      ;;
    *)
      fail "rollback found unknown recovery state: $status"
      return 1
      ;;
  esac
  assert_installed_surface "$status" || return 1
  assert_new_boot || return 1
  arming_boot_id="$(state_field arming_boot_id)" || return 1
  completion_boot_id="$(current_boot_id)" || return 1

  run_boot_transaction rollback-boot ||
    fail 'persistent recovery could not restore exact no-boot generation two' ||
    return 1
  disable_timer_link || return 1
  if [[ "$status" == armed ]]; then
    write_state rolled-back "$arming_boot_id" "$completion_boot_id" || return 1
  fi
  systemctl daemon-reload || return 1
  run_boot_transaction verify-before || return 1
  pass recovery_rollback 'exact no-boot generation two restored; recovery evidence retained for cleanup'
}

remove_exact_recovery_surface() {
  local expected_status="$1"

  assert_installed_surface "$expected_status" || return 1
  systemctl stop "$timer_unit" >/dev/null 2>&1 || true
  systemctl stop "$service_unit" >/dev/null 2>&1 || true
  systemctl reset-failed "$timer_unit" "$service_unit" >/dev/null 2>&1 || true
  disable_timer_link || return 1

  [[ -L "$timer_path" && "$(readlink -- "$timer_path")" == "$bundle_timer" ]] ||
    fail 'refusing to remove unknown recovery timer path' || return 1
  unlink -- "$timer_path" || return 1
  [[ -L "$service_path" && "$(readlink -- "$service_path")" == "$bundle_service" ]] ||
    fail 'refusing to remove unknown recovery service path' || return 1
  unlink -- "$service_path" || return 1
  [[ -f "$state_path" && ! -L "$state_path" ]] ||
    fail 'refusing to remove unknown recovery state path' || return 1
  unlink -- "$state_path" || return 1
  rmdir -- "$state_dir" || return 1
  rmdir -- "$state_parent" 2>/dev/null || true
  [[ -L "$recovery_root" && "$(readlink -- "$recovery_root")" == "$bundle" ]] ||
    fail 'refusing to remove unknown recovery GC root' || return 1
  unlink -- "$recovery_root" || return 1
  systemctl daemon-reload || return 1
  assert_surface_absent
}

confirm_recovery() {
  local phrase="$1"

  [[ "$phrase" == "$confirmation_phrase" ]] ||
    fail 'post-boot confirmation phrase did not match' || return 1
  acquire_lock || return 1
  verify_armed_postboot || return 1
  remove_exact_recovery_surface armed || return 1
  verify_generation_three_postboot absent || return 1
  pass recovery_confirmed 'generation-three reboot retained and persistent rollback removed'
}

verify_rolled_back() {
  assert_installed_surface rolled-back || return 1
  assert_new_boot || return 1
  run_boot_transaction verify-before || return 1
  [[ "$(systemctl show "$timer_unit" -p ActiveState --value 2>/dev/null || true)" != active ]] ||
    fail 'rolled-back recovery timer remains active' || return 1
  [[ "$(systemctl show "$service_unit" -p ActiveState --value 2>/dev/null || true)" != active ]] ||
    fail 'rolled-back recovery service remains active' || return 1
  pass recovery_rolled_back 'generation two is live/no-boot and recovery evidence awaits exact cleanup'
}

cleanup_rolled_back() {
  local phrase="$1"

  [[ "$phrase" == "$cleanup_phrase" ]] ||
    fail 'rolled-back recovery cleanup phrase did not match' || return 1
  acquire_lock || return 1
  verify_rolled_back || return 1
  remove_exact_recovery_surface rolled-back || return 1
  run_boot_transaction verify-before || return 1
  pass recovery_cleanup 'rolled-back recovery surface removed after exact verification'
}

if [[ "$EUID" -ne 0 ]]; then
  fail 'run reboot recovery as root'
  exit 1
fi

validate_compiled_inputs || exit 1

action="${1:-}"
case "$action" in
  arm | verify-armed-preboot | disarm-preboot | verify-armed-postboot | rollback | verify-rolled-back)
    [[ "$#" -eq 1 ]] || {
      usage
      exit 2
    }
    ;;
  confirm | cleanup-rolled-back)
    [[ "$#" -eq 2 ]] || {
      usage
      exit 2
    }
    ;;
  *)
    usage
    exit 2
    ;;
esac

case "$action" in
  arm)
    arm_recovery
    ;;
  verify-armed-preboot)
    verify_armed_preboot
    ;;
  disarm-preboot)
    disarm_preboot
    ;;
  verify-armed-postboot)
    verify_armed_postboot
    ;;
  rollback)
    rollback_recovery
    ;;
  verify-rolled-back)
    verify_rolled_back
    ;;
  confirm)
    confirm_recovery "$2"
    ;;
  cleanup-rolled-back)
    cleanup_rolled_back "$2"
    ;;
esac
