#!/usr/bin/env bash
set -uo pipefail

# Generic first-deployment System Manager transaction for a declared DGX host.
# It intentionally does not know sparkle-01's historical generation numbers.
# A pristine host registers the factory-mode candidate as generation one; a
# selected headless host later registers the headless candidate as generation
# two.  The guarded fleet operator owns snapshots, timers, and confirmation.

profile_dir=/nix/var/nix/profiles/system-manager-profiles
profile_path=$profile_dir/system-manager
gcroot_path=/nix/var/nix/gcroots/system-manager-current
state_path=/var/lib/system-manager/state/system-manager-state.json
factory_root=/nix/var/nix/gcroots/dgx-setup-fleet-factory
headless_root=/nix/var/nix/gcroots/dgx-setup-fleet-headless
vendor_unit=/usr/lib/systemd/system/tailscaled.service
vendor_wants=/etc/systemd/system/multi-user.target.wants/tailscaled.service
managed_unit=/etc/systemd/system/tailscaled.service

usage() {
  printf 'Usage: %s <install-factory | rollback-pristine | verify-pristine | install-headless | rollback-factory | verify-factory | verify-headless> FACTORY HEADLESS\n' "$(basename "$0")" >&2
}

info() {
  printf 'INFO|%s|%s\n' "$1" "$2"
}

pass() {
  printf 'PASS|%s|%s\n' "$1" "$2"
}

fail() {
  printf 'FAIL|fleet_bootstrap_transaction|%s\n' "$1" >&2
  return 1
}

path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

raw_link() {
  readlink -- "$1" 2>/dev/null || true
}

resolved_link() {
  readlink -f -- "$1" 2>/dev/null || true
}

candidate_entry_source() {
  local candidate="$1" entry="$2"

  jq -er --arg entry "$entry" '.entries[$entry].source' \
    "$candidate/etcFiles/etcFiles.json"
}

candidate_marker() {
  local candidate="$1" entry="$2" source target

  source="$(candidate_entry_source "$candidate" "$entry")" || return 1
  target="$(jq -er --arg entry "$entry" '.entries[$entry].target' \
    "$candidate/etcFiles/etcFiles.json")" || return 1
  readlink -f -- "$source/$target"
}

candidate_unit_tree() {
  local source

  source="$(candidate_entry_source "$1" systemd/system)" || return 1
  readlink -f -- "$source/systemd/system"
}

candidate_service_path() {
  jq -er --arg unit "$2" '.[$unit].storePath' "$1/services/services.json"
}

candidate_has_service() {
  jq -e --arg unit "$2" 'has($unit)' "$1/services/services.json" >/dev/null
}

candidate_tailscale_selected() {
  grep -Fx 'tailscale-selected=true' "$(candidate_marker "$1" dgx-setup/canary)" >/dev/null
}

assert_candidate_shape() {
  local candidate unit_tree

  for candidate in "$factory" "$headless"; do
    [[ "$candidate" =~ ^/nix/store/[a-z0-9]{32}-system-manager$ ]] ||
      fail "candidate is not an exact System Manager output: $candidate" || return 1
    [[ -d "$candidate" && -x "$candidate/bin/activate" &&
      -x "$candidate/bin/deactivate" && -x "$candidate/bin/register-profile" &&
      -r "$candidate/etcFiles/etcFiles.json" &&
      -r "$candidate/services/services.json" ]] ||
      fail "candidate programs or metadata are unavailable: $candidate" || return 1
    grep -Fx "host=$host_name" "$(candidate_marker "$candidate" dgx-setup/canary)" >/dev/null ||
      fail "candidate belongs to another host: $candidate" || return 1
    unit_tree="$(candidate_unit_tree "$candidate")" || return 1
    [[ -d "$unit_tree" ]] || fail "candidate unit tree is unavailable" || return 1
  done

  [[ "$factory" != "$headless" ]] || fail "factory and headless candidates are identical" || return 1
  grep -Fx 'desktop-mode=gnome' "$(candidate_marker "$factory" dgx-setup/canary)" >/dev/null ||
    fail "factory candidate is not GNOME mode" || return 1
  grep -Fx 'desktop-mode=headless' "$(candidate_marker "$headless" dgx-setup/canary)" >/dev/null ||
    fail "headless candidate is not headless mode" || return 1
  if candidate_tailscale_selected "$factory"; then
    candidate_tailscale_selected "$headless" ||
      fail "headless candidate dropped selected Tailscale" || return 1
    candidate_has_service "$factory" tailscaled.service ||
      fail "factory candidate lacks selected tailscaled.service" || return 1
    candidate_has_service "$headless" tailscaled.service ||
      fail "headless candidate lacks selected tailscaled.service" || return 1
  else
    ! candidate_tailscale_selected "$headless" ||
      fail "desktop candidates disagree about Tailscale selection" || return 1
    ! candidate_has_service "$factory" tailscaled.service ||
      fail "unselected factory candidate owns tailscaled.service" || return 1
    ! candidate_has_service "$headless" tailscaled.service ||
      fail "unselected headless candidate owns tailscaled.service" || return 1
  fi
}

assert_root() {
  local path="$1" target="$2"

  [[ -L "$path" && "$(raw_link "$path")" == "$target" ]] ||
    fail "exact candidate root is missing: $path" || return 1
}

assert_profile() {
  local generation="$1" candidate="$2" expected_link

  expected_link="system-manager-${generation}-link"
  [[ -L "$profile_path" && "$(raw_link "$profile_path")" == "$expected_link" &&
    "$(resolved_link "$profile_path")" == "$candidate" ]] ||
    fail "System Manager profile is not exact generation $generation" || return 1
  [[ -L "$profile_dir/$expected_link" &&
    "$(raw_link "$profile_dir/$expected_link")" == "$candidate" ]] ||
    fail "generation link is not exact: $expected_link" || return 1
  [[ -L "$gcroot_path" && "$(raw_link "$gcroot_path")" == "$candidate" ]] ||
    fail "upstream System Manager GC root is not exact" || return 1
}

assert_profile_entries() {
  local expected="$1" observed

  observed="$(find "$profile_dir" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort)"
  [[ "$observed" == "$expected" ]] ||
    fail "unexpected System Manager profile surface: ${observed:-ABSENT}" || return 1
}

assert_live_candidate() {
  local candidate="$1" marker unit expected tree relative live

  marker="$(candidate_marker "$candidate" dgx-setup/canary)" || return 1
  [[ -L /etc/dgx-setup/canary &&
    "$(resolved_link /etc/dgx-setup/canary)" == "$marker" ]] ||
    fail "live fleet marker does not match the candidate" || return 1
  marker="$(candidate_marker "$candidate" dgx-setup/desktop-mode)" || return 1
  [[ -L /etc/dgx-setup/desktop-mode &&
    "$(resolved_link /etc/dgx-setup/desktop-mode)" == "$marker" ]] ||
    fail "live desktop marker does not match the candidate" || return 1

  for unit in dgx-setup-canary.service sysinit-reactivation.target system-manager.target; do
    expected="$(candidate_service_path "$candidate" "$unit")" || return 1
    live="$(systemctl show "$unit" -p FragmentPath --value 2>/dev/null || true)"
    [[ "$live" == "$expected" ]] || fail "live unit does not match candidate: $unit" || return 1
  done
  systemctl is-active --quiet system-manager.target ||
    fail "system-manager.target is not active" || return 1
  systemctl is-active --quiet dgx-setup-canary.service ||
    fail "fleet canary service is not active" || return 1

  tree="$(candidate_unit_tree "$candidate")" || return 1
  while IFS= read -r relative; do
    expected="$(readlink -f -- "$tree/$relative")"
    [[ -L "/etc/systemd/system/$relative" &&
      "$(resolved_link "/etc/systemd/system/$relative")" == "$expected" ]] ||
      fail "managed systemd path does not match candidate: $relative" || return 1
  done < <(find -L "$tree" -type f -printf '%P\n' | sort)

  [[ -f "$state_path" ]] || fail "System Manager state file is absent" || return 1
  jq -e '.version == 1' "$state_path" >/dev/null ||
    fail "System Manager state is not version one" || return 1

  if candidate_tailscale_selected "$candidate"; then
    expected="$(candidate_service_path "$candidate" tailscaled.service)" || return 1
    [[ "$(systemctl show tailscaled.service -p FragmentPath --value 2>/dev/null || true)" == "$expected" ]] ||
      fail "running tailscaled.service is not Nix-managed" || return 1
    systemctl is-active --quiet tailscaled.service ||
      fail "Nix-managed tailscaled.service is not active" || return 1
  fi
}

assert_factory_runtime() {
  [[ "$(systemctl get-default 2>/dev/null || true)" == default.target ]] ||
    fail "managed factory dispatcher is not the default target" || return 1
  systemctl is-active --quiet graphical.target ||
    fail "factory graphical target is not active" || return 1
  systemctl is-active --quiet gdm.service || fail "factory GDM is not active" || return 1
  systemctl is-active --quiet dgx-dashboard.service ||
    fail "factory Dashboard GUI is not active" || return 1
}

assert_headless_runtime() {
  [[ "$(systemctl get-default 2>/dev/null || true)" == default.target ]] ||
    fail "managed headless dispatcher is not the default target" || return 1
  systemctl is-active --quiet dgx-headless.target ||
    fail "DGX headless target is not active" || return 1
  ! systemctl is-active --quiet graphical.target ||
    fail "graphical.target remains active in headless mode" || return 1
  ! systemctl is-active --quiet gdm.service ||
    fail "factory GDM remains active in headless mode" || return 1
  ! systemctl is-active --quiet dgx-dashboard.service ||
    fail "factory Dashboard GUI remains active in headless mode" || return 1
}

assert_empty_state() {
  if path_exists "$state_path"; then
    [[ -f "$state_path" && ! -L "$state_path" ]] ||
      fail "residual System Manager state is not a regular file" || return 1
    jq -e '
      .version == 0 and
      ((.fileTree.files // []) | length == 0) and
      ((.fileTree.backedUpFiles // []) | length == 0) and
      ((.services // {}) | length == 0)
    ' "$state_path" >/dev/null || fail "residual System Manager state is not empty" || return 1
  fi
}

assert_pristine() {
  local path

  ! path_exists "$profile_dir" || {
    [[ -d "$profile_dir" && ! -L "$profile_dir" &&
      -z "$(find "$profile_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]] ||
      fail "System Manager profile surface is not pristine" || return 1
  }
  ! path_exists "$gcroot_path" || fail "System Manager GC root already exists" || return 1
  assert_empty_state || return 1
  for path in /etc/dgx-setup/canary /etc/dgx-setup/desktop-mode \
    /etc/systemd/system/default.target \
    /etc/systemd/system/default.target.wants/system-manager.target \
    /etc/systemd/system/dgx-headless.target /etc/systemd/system/dgx-gnome.target \
    /etc/systemd/system/dgx-setup-canary.service \
    /etc/systemd/system/sysinit-reactivation.target \
    /etc/systemd/system/system-manager.target \
    /etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service \
    /etc/systemd/system/system-manager.target.wants/tailscaled.service \
    "$managed_unit"; do
    ! path_exists "$path" || fail "managed path exists before first deployment: $path" || return 1
  done
  pass pristine "System Manager registration and managed root surface are absent"
}

verify_factory() {
  assert_root "$factory_root" "$factory" || return 1
  assert_profile_entries $'system-manager\nsystem-manager-1-link' || return 1
  assert_profile 1 "$factory" || return 1
  assert_live_candidate "$factory" || return 1
  assert_factory_runtime || return 1
  pass factory "first fleet generation is selected, live, boot-linked, and factory graphical"
}

verify_headless() {
  assert_root "$factory_root" "$factory" || return 1
  assert_root "$headless_root" "$headless" || return 1
  assert_profile_entries $'system-manager\nsystem-manager-1-link\nsystem-manager-2-link' || return 1
  assert_profile 2 "$headless" || return 1
  assert_live_candidate "$headless" || return 1
  assert_headless_runtime || return 1
  pass headless "second fleet generation is selected, live, boot-linked, and headless"
}

remove_empty_state() {
  assert_empty_state || return 1
  if path_exists "$state_path"; then
    rm -f -- "$state_path" || return 1
  fi
  rmdir --ignore-fail-on-non-empty /var/lib/system-manager/state \
    /var/lib/system-manager 2>/dev/null || true
}

sync_gcroot() {
  local target="$1" temporary

  if path_exists "$gcroot_path"; then
    [[ -L "$gcroot_path" ]] || fail "upstream GC root is a foreign collision" || return 1
  fi
  temporary="$gcroot_path.dgx-fleet-$$"
  ! path_exists "$temporary" || fail "temporary GC root collision" || return 1
  ln -s -- "$target" "$temporary" || return 1
  mv -Tf -- "$temporary" "$gcroot_path" || return 1
}

activate_exact() {
  local candidate="$1" logs status=0

  logs="$("$candidate/bin/activate" 2>&1)" || status=$?
  printf '%s\n' "$logs"
  ((status == 0)) || return "$status"
  ! grep -q ' ERROR ' <<<"$logs" || fail "System Manager activation logged an error"
}

restore_vendor_tailscale() {
  if [[ -f "$vendor_unit" && -L "$vendor_wants" &&
    "$(resolved_link "$vendor_wants")" == "$vendor_unit" ]]; then
    systemctl reset-failed tailscaled.service 2>/dev/null || true
    systemctl start tailscaled.service ||
      fail "vendor Tailscale could not be restored" || return 1
    [[ "$(systemctl show tailscaled.service -p FragmentPath --value 2>/dev/null || true)" == "$vendor_unit" ]] ||
      fail "restored tailscaled.service is not the vendor unit" || return 1
  elif path_exists "$vendor_wants"; then
    fail "vendor Tailscale enablement is an unknown collision" || return 1
  fi
}

restore_absent_tailscale_state() {
  local mode owner

  [[ "${DGX_FLEET_BOOTSTRAP_TAILSCALE_WAS_ABSENT:-}" == 1 ]] || return 0
  # This cleanup is only valid for a genuinely package-free fresh host. If a
  # vendor daemon exists or any daemon is still running, retain the state and
  # stop rather than deleting data another owner may need.
  [[ ! -e "$vendor_unit" && ! -L "$vendor_unit" ]] || return 0
  ! systemctl is-active --quiet tailscaled.service ||
    fail "refusing to remove newly created Tailscale state while a daemon is active" || return 1
  if path_exists /var/lib/tailscale/tailscaled.state; then
    [[ -f /var/lib/tailscale/tailscaled.state &&
      ! -L /var/lib/tailscale/tailscaled.state ]] ||
      fail "new Tailscale state has an unsafe file type" || return 1
    mode="$(stat -c %a /var/lib/tailscale/tailscaled.state)"
    owner="$(stat -c %u /var/lib/tailscale/tailscaled.state)"
    [[ "$mode" == 600 && "$owner" == 0 ]] ||
      fail "new Tailscale state has unsafe ownership or mode" || return 1
    rm -f -- /var/lib/tailscale/tailscaled.state || return 1
  fi
}

rollback_pristine() {
  local activation_status=0 expected_marker

  assert_candidate_shape || return 1
  if path_exists /etc/dgx-setup/canary; then
    expected_marker="$(candidate_marker "$factory" dgx-setup/canary)" || return 1
    [[ -L /etc/dgx-setup/canary &&
      "$(resolved_link /etc/dgx-setup/canary)" == "$expected_marker" ]] ||
      fail "refusing pristine rollback from an unknown live activation" || return 1
    "$factory/bin/deactivate" || activation_status=$?
  fi
  systemctl daemon-reload || return 1
  restore_vendor_tailscale || return 1
  restore_absent_tailscale_state || return 1
  if path_exists "$profile_dir/system-manager-1-link"; then
    [[ -L "$profile_dir/system-manager-1-link" &&
      "$(raw_link "$profile_dir/system-manager-1-link")" == "$factory" ]] ||
      fail "refusing to remove an unknown first generation" || return 1
    rm -f -- "$profile_path" "$profile_dir/system-manager-1-link" "$gcroot_path" || return 1
  fi
  if [[ -d "$profile_dir" && ! -L "$profile_dir" ]]; then
    [[ -z "$(find "$profile_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]] ||
      fail "unknown profile entries remain after rollback" || return 1
    rmdir -- "$profile_dir" || return 1
  fi
  remove_empty_state || return 1
  systemctl start graphical.target gdm.service dgx-dashboard.service ||
    fail "factory graphical services could not be restored" || return 1
  assert_pristine >/dev/null || return 1
  ((activation_status == 0)) ||
    fail "deactivation reported failure despite exact pristine recovery" || return 1
  pass rollback "pristine System Manager boundary and factory services restored"
}

validate_injection() {
  local stage="${DGX_FLEET_BOOTSTRAP_TEST_FAIL_STAGE:-}"

  [[ -n "$stage" ]] || return 0
  case "$stage" in
    factory-after-registration | factory-after-activation | \
      headless-after-registration | headless-after-activation | headless-after-isolate) ;;
    *) fail "unknown disposable failure-injection stage: $stage"; return 1 ;;
  esac
  [[ -r /run/systemd/container && "$(</run/systemd/container)" == systemd-nspawn ]] ||
    fail "failure injection is allowed only in a systemd-nspawn container" || return 1
}

install_factory() {
  validate_injection || return 1
  assert_candidate_shape || return 1
  assert_root "$factory_root" "$factory" || return 1
  assert_pristine >/dev/null || return 1

  "$factory/bin/register-profile" || {
    rollback_pristine || true
    fail "first-generation registration failed; pristine rollback was attempted"
    return 1
  }
  if [[ "${DGX_FLEET_BOOTSTRAP_TEST_FAIL_STAGE:-}" == factory-after-registration ]]; then
    rollback_pristine || return 1
    fail "disposable post-registration failure injected after successful rollback"
    return 1
  fi
  activate_exact "$factory" || {
    rollback_pristine || true
    fail "factory activation failed; pristine rollback was attempted"
    return 1
  }
  if [[ "${DGX_FLEET_BOOTSTRAP_TEST_FAIL_STAGE:-}" == factory-after-activation ]]; then
    rollback_pristine || return 1
    fail "disposable post-activation failure injected after successful rollback"
    return 1
  fi
  if candidate_tailscale_selected "$factory"; then
    systemctl restart tailscaled.service || {
      rollback_pristine || true
      fail "Nix-managed Tailscale restart failed; pristine rollback was attempted"
      return 1
    }
  fi
  verify_factory || {
    rollback_pristine || true
    fail "factory postflight failed; pristine rollback was attempted"
    return 1
  }
  pass transaction "factory candidate registered and activated as first generation"
}

restore_factory() {
  local headless_link=$profile_dir/system-manager-2-link
  local live_marker factory_marker headless_marker

  assert_candidate_shape || return 1
  assert_root "$factory_root" "$factory" || return 1
  assert_root "$headless_root" "$headless" || return 1
  factory_marker="$(candidate_marker "$factory" dgx-setup/canary)" || return 1
  headless_marker="$(candidate_marker "$headless" dgx-setup/canary)" || return 1
  live_marker="$(resolved_link /etc/dgx-setup/canary)"
  case "$live_marker" in
    "$factory_marker" | "$headless_marker") ;;
    *) fail "refusing factory rollback from an unknown live activation"; return 1 ;;
  esac
  if ! assert_live_candidate "$factory" >/dev/null 2>&1 ||
    ! assert_factory_runtime >/dev/null 2>&1; then
    activate_exact "$factory" || fail "factory rollback activation failed" || return 1
    systemctl start system-manager.target dgx-gnome.target ||
      fail "factory graphical target could not be restored" || return 1
  fi
  if [[ "$(resolved_link "$profile_path")" != "$factory" ]]; then
    /nix/var/nix/profiles/default/bin/nix-env \
      --profile "$profile_path" --switch-generation 1 ||
      fail "could not select first fleet generation" || return 1
  fi
  if path_exists "$headless_link"; then
    [[ -L "$headless_link" && "$(raw_link "$headless_link")" == "$headless" ]] ||
      fail "refusing to remove an unknown second generation" || return 1
    rm -f -- "$headless_link" || return 1
  fi
  sync_gcroot "$factory" || return 1
  verify_factory || return 1
  pass rollback "first fleet generation and factory GNOME restored"
}

install_headless() {
  validate_injection || return 1
  assert_candidate_shape || return 1
  assert_root "$factory_root" "$factory" || return 1
  assert_root "$headless_root" "$headless" || return 1
  verify_factory >/dev/null || return 1

  "$headless/bin/register-profile" || {
    restore_factory || true
    fail "headless registration failed; factory rollback was attempted"
    return 1
  }
  if [[ "${DGX_FLEET_BOOTSTRAP_TEST_FAIL_STAGE:-}" == headless-after-registration ]]; then
    restore_factory || return 1
    fail "disposable post-registration failure injected after successful rollback"
    return 1
  fi
  activate_exact "$headless" || {
    restore_factory || true
    fail "headless activation failed; factory rollback was attempted"
    return 1
  }
  if [[ "${DGX_FLEET_BOOTSTRAP_TEST_FAIL_STAGE:-}" == headless-after-activation ]]; then
    restore_factory || return 1
    fail "disposable post-activation failure injected after successful rollback"
    return 1
  fi
  systemctl isolate dgx-headless.target || {
    restore_factory || true
    fail "headless isolation failed; factory rollback was attempted"
    return 1
  }
  if [[ "${DGX_FLEET_BOOTSTRAP_TEST_FAIL_STAGE:-}" == headless-after-isolate ]]; then
    restore_factory || return 1
    fail "disposable post-isolation failure injected after successful rollback"
    return 1
  fi
  verify_headless || {
    restore_factory || true
    fail "headless postflight failed; factory rollback was attempted"
    return 1
  }
  pass transaction "headless candidate registered and activated as second generation"
}

if [[ "$EUID" -ne 0 ]]; then
  fail "run this transaction as root"
  exit 1
fi
if [[ "$#" -ne 3 ]]; then
  usage
  exit 2
fi

action="$1"
factory="$2"
headless="$3"
host_name="$(hostname -s)"

case "$action" in
  install-factory) install_factory ;;
  rollback-pristine) rollback_pristine ;;
  verify-pristine) assert_candidate_shape && assert_pristine ;;
  install-headless) install_headless ;;
  rollback-factory) restore_factory ;;
  verify-factory) assert_candidate_shape && verify_factory ;;
  verify-headless) assert_candidate_shape && verify_headless ;;
  *) usage; exit 2 ;;
esac
