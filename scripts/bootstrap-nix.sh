#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fleet_file=$repo_dir/fleet/hosts.json
source_file=$repo_dir/bootstrap/nix/source.json
nix_bin=/nix/var/nix/profiles/default/bin/nix

fail() {
  printf 'FAIL|nix_bootstrap|%s\n' "$1" >&2
  exit 1
}

json_value() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

path, expression = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    value = json.load(handle)
for component in expression.split("."):
    value = value[component]
if isinstance(value, bool):
    print(str(value).lower())
else:
    print(value)
PY
}

receipt_matches_base() {
  python3 - /nix/receipt.json "$source_file" <<'PY'
import json
import sys

receipt_path, source_path = sys.argv[1:]
with open(receipt_path, encoding="utf-8") as handle:
    receipt = json.load(handle)
with open(source_path, encoding="utf-8") as handle:
    source = json.load(handle)

planner = receipt.get("planner", {})
settings = planner.get("settings", {})
init = planner.get("init", {})
expected = source["linuxPlanner"]
checks = {
    "installer_version": receipt.get("version") == source["installer"]["version"],
    "planner": planner.get("planner") == "linux",
    "init": init.get("init") == "Systemd",
    "start_daemon": init.get("start_daemon") is expected["startDaemon"],
    "modify_profile": settings.get("modify_profile") is expected["modifyProfile"],
    "build_group_name": settings.get("nix_build_group_name") == expected["buildGroupName"],
    "build_group_id": settings.get("nix_build_group_id") == expected["buildGroupId"],
    "build_user_prefix": settings.get("nix_build_user_prefix") == expected["buildUserPrefix"],
    "build_user_count": settings.get("nix_build_user_count") == expected["buildUserCount"],
    "build_user_id_base": settings.get("nix_build_user_id_base") == expected["buildUserIdBase"],
    "no_channel": settings.get("add_channel") is expected["addChannel"],
    "default_tls": settings.get("ssl_cert_file") is None,
    "no_extra_conf": settings.get("extra_conf") == [],
    "not_forced": settings.get("force") is False,
    "nix_conf_owned": settings.get("skip_nix_conf") is False,
}
failed = [name for name, passed in checks.items() if not passed]
if failed:
    raise SystemExit("receipt base mismatch: " + ",".join(failed))
print(str(settings.get("enable_flakes", False)).lower())
PY
}

capture_protected_units() {
  local unit load_state
  for unit in tailscaled.service gdm.service docker.service \
    dgx-dashboard.service dgx-dashboard-admin.service \
    nvidia-persistenced.service; do
    load_state="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
    [[ "$load_state" != not-found && -n "$load_state" ]] || continue
    printf '%s|' "$unit"
    systemctl show "$unit" -p ActiveState -p FragmentPath -p MainPID \
      -p ActiveEnterTimestampMonotonic --value | paste -sd '|'
  done
}

capture_gpu() {
  nvidia-smi --query-gpu=name,driver_version --format=csv,noheader,nounits
}

capture_tailscale() {
  local status_json prefs_json
  if ! command -v tailscale >/dev/null 2>&1; then
    printf '%s\n' 'ABSENT'
    return
  fi
  status_json="$(timeout 10s tailscale status --json 2>/dev/null || true)"
  prefs_json="$(timeout 10s tailscale debug prefs 2>/dev/null || true)"
  python3 - 3<<<"$status_json" 4<<<"$prefs_json" <<'PY'
import json
import os

try:
    status = json.load(os.fdopen(3))
    prefs = json.load(os.fdopen(4))
except (json.JSONDecodeError, OSError):
    print("backend=UNKNOWN;online=UNKNOWN;want_running=UNKNOWN;run_ssh=UNKNOWN")
else:
    def value(item):
        if isinstance(item, bool):
            return str(item).lower()
        return item if item is not None else "UNKNOWN"

    print(
        f"backend={value(status.get('BackendState'))};"
        f"online={value(status.get('Self', {}).get('Online'))};"
        f"want_running={value(prefs.get('WantRunning'))};"
        f"run_ssh={value(prefs.get('RunSSH'))}"
    )
PY
}

capture_rollback_files() {
  local path
  for path in /etc/passwd /etc/group /etc/shadow /etc/gshadow \
    /etc/bashrc /etc/bash.bashrc /etc/zshrc /etc/zsh/zshrc \
    /etc/profile.d/nix.sh /usr/share/fish/vendor_conf.d/nix.fish \
    /root/.nix-profile /root/.nix-defexpr /root/.nix-channels \
    /root/.local/state/nix /root/.cache/nix; do
    if [[ -e "$path" ]]; then
      printf 'SHA256\t%s\t%s\n' "$path" "$(sha256sum "$path" | awk '{print $1}')"
    else
      printf 'ABSENT\t%s\t-\n' "$path"
    fi
  done
}

verify_existing() {
  local installer_version installer_sha256 installer_size desired_runtime
  local observed_runtime receipt_flakes features daemon_state socket_state
  installer_version="$(json_value "$source_file" installer.version)"
  installer_sha256="$(json_value "$source_file" installer.sha256)"
  installer_size="$(json_value "$source_file" installer.size)"
  desired_runtime="$(json_value "$source_file" desiredRuntime.version)"

  [[ -x /nix/nix-installer && -r /nix/receipt.json && -x "$nix_bin" ]] ||
    fail 'existing Nix surface is incomplete or foreign; refusing adoption'
  [[ "$(/nix/nix-installer --version | awk '{print $NF}')" == "$installer_version" ]] ||
    fail 'installed provisioning binary version differs from the repository pin'
  [[ "$(sha256sum /nix/nix-installer | awk '{print $1}')" == "$installer_sha256" ]] ||
    fail 'installed provisioning binary checksum differs from the repository pin'
  [[ "$(stat -c %s /nix/nix-installer)" == "$installer_size" ]] ||
    fail 'installed provisioning binary size differs from the repository pin'
  receipt_flakes="$(receipt_matches_base)" ||
    fail 'installed receipt does not match the reviewed Linux planner base'
  observed_runtime="$($nix_bin --version | awk '{print $NF}')"
  [[ "$observed_runtime" == "$desired_runtime" ]] ||
    fail "running Nix is $observed_runtime, expected $desired_runtime; use the reviewed runtime update path"
  socket_state="$(systemctl is-active nix-daemon.socket 2>/dev/null || true)"
  daemon_state="$(systemctl is-active nix-daemon.service 2>/dev/null || true)"
  [[ "$socket_state" == active || "$daemon_state" == active ]] ||
    fail 'neither the Nix daemon socket nor service is active'
  "$nix_bin" --extra-experimental-features 'nix-command flakes' store info \
    >/dev/null 2>&1
  features="$($nix_bin config show experimental-features 2>/dev/null || true)"

  printf 'PASS|nix_bootstrap|adopted exact installer %s and healthy runtime %s\n' \
    "$installer_version" "$observed_runtime"
  if [[ "$receipt_flakes" == true && " $features " == *' flakes '* ]]; then
    printf '%s\n' 'PASS|nix_features|flakes were enabled by the original install plan'
  else
    printf 'HOLD|nix_features|receipt_enable_flakes=%s;persistent=%s;adoption made no config change\n' \
      "$receipt_flakes" "${features:-NONE}"
  fi
  printf '%s\n' 'PASS|nix_bootstrap|existing installation adopted with zero mutation'
  printf '%s\n' 'BOOTSTRAP_STATUS=ADOPTED'
}

surface_is_clean() {
  local path index nix_path
  local dirty=0
  local -a paths=(
    /nix
    /etc/nix
    /root/.nix-profile
    /root/.nix-defexpr
    /root/.nix-channels
    /root/.local/state/nix
    /root/.cache/nix
    /etc/profile.d/nix.sh
    /etc/tmpfiles.d/nix-daemon.conf
    /etc/systemd/system/nix-daemon.service
    /etc/systemd/system/nix-daemon.socket
    /etc/systemd/system/multi-user.target.wants/nix-daemon.service
    /etc/systemd/system/sockets.target.wants/nix-daemon.socket
  )
  for path in "${paths[@]}"; do
    if [[ -e "$path" || -L "$path" ]]; then
      printf 'DIRTY|nix_surface|path=%s\n' "$path" >&2
      dirty=1
    fi
  done
  if nix_path="$(command -v nix 2>/dev/null)"; then
    printf 'DIRTY|nix_surface|command=nix;path=%s\n' "$nix_path" >&2
    dirty=1
  fi
  if getent group "$(json_value "$source_file" linuxPlanner.buildGroupName)" >/dev/null; then
    printf 'DIRTY|nix_surface|group=%s\n' \
      "$(json_value "$source_file" linuxPlanner.buildGroupName)" >&2
    dirty=1
  fi
  for ((index = 1; index <= $(json_value "$source_file" linuxPlanner.buildUserCount); index++)); do
    if getent passwd "$(json_value "$source_file" linuxPlanner.buildUserPrefix)$index" >/dev/null; then
      printf 'DIRTY|nix_surface|user=%s%s\n' \
        "$(json_value "$source_file" linuxPlanner.buildUserPrefix)" "$index" >&2
      dirty=1
    fi
  done
  [[ "$dirty" -eq 0 ]]
}

root_install() {
  local target_host=$1 expected_commit=$2 declared_user=$3
  local stamp evidence_dir timer_unit service_unit installer_url installer_version
  local installer_sha256 installer_size desired_runtime observed_runtime
  local group_name group_id user_prefix user_count user_id_base
  local current_commit plan_flakes features tailscale_before installer_file

  [[ "$EUID" -eq 0 ]] || fail 'internal install phase must run as root'
  [[ "${SUDO_USER:-}" == "$declared_user" ]] ||
    fail 'sudo caller does not match the declared managed user'
  current_commit="$(git -c safe.directory="$repo_dir" -C "$repo_dir" rev-parse HEAD)"
  [[ "$current_commit" == "$expected_commit" ]] || fail 'repository commit changed across sudo'
  [[ -z "$(git -c safe.directory="$repo_dir" -C "$repo_dir" status --porcelain=v1)" ]] ||
    fail 'repository must remain clean during bootstrap'
  surface_is_clean || fail 'Nix surface appeared before installation; refusing overwrite'

  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  evidence_dir="/var/lib/dgx-setup/nix-bootstrap/$stamp"
  install -d -o root -g root -m 0700 "$evidence_dir"
  install -o root -g root -m 0600 "$source_file" "$evidence_dir/source.json"
  install -o root -g root -m 0600 "$fleet_file" "$evidence_dir/hosts.json"
  install -o root -g root -m 0700 \
    "$repo_dir/scripts/rollback-fresh-nix-bootstrap.sh" "$evidence_dir/rollback.sh"
  printf 'timestamp_utc=%s\nhost=%s\nrepo_commit=%s\ndeclared_user=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$target_host" "$current_commit" "$declared_user" \
    >"$evidence_dir/context.txt"
  chmod 0600 "$evidence_dir/context.txt"
  [[ "$(systemctl is-system-running)" == running ]] ||
    fail 'systemd is not healthy before bootstrap'
  capture_protected_units >"$evidence_dir/protected-units.before.tsv"
  capture_gpu >"$evidence_dir/gpu.before.txt"
  capture_rollback_files >"$evidence_dir/rollback-files.before.tsv"
  tailscale_before="$(capture_tailscale)"
  printf '%s\n' "$tailscale_before" >"$evidence_dir/tailscale.before.txt"
  if [[ "$tailscale_before" != ABSENT &&
        "$tailscale_before" != 'backend=Running;online=true;want_running=true;run_ssh=true' ]]; then
    fail 'existing Tailscale/SSH state is not healthy before bootstrap'
  fi
  chmod 0600 "$evidence_dir/protected-units.before.tsv" \
    "$evidence_dir/gpu.before.txt" "$evidence_dir/rollback-files.before.tsv" \
    "$evidence_dir/tailscale.before.txt"

  installer_url="$(json_value "$source_file" installer.url)"
  installer_version="$(json_value "$source_file" installer.version)"
  installer_sha256="$(json_value "$source_file" installer.sha256)"
  installer_size="$(json_value "$source_file" installer.size)"
  desired_runtime="$(json_value "$source_file" desiredRuntime.version)"
  group_name="$(json_value "$source_file" linuxPlanner.buildGroupName)"
  group_id="$(json_value "$source_file" linuxPlanner.buildGroupId)"
  user_prefix="$(json_value "$source_file" linuxPlanner.buildUserPrefix)"
  user_count="$(json_value "$source_file" linuxPlanner.buildUserCount)"
  user_id_base="$(json_value "$source_file" linuxPlanner.buildUserIdBase)"

  installer_file=${DGX_NIX_BOOTSTRAP_PRESEEDED_INSTALLER:-}
  if [[ -n "$installer_file" ]]; then
    [[ -f "$installer_file" && ! -L "$installer_file" ]] ||
      fail 'preseeded installer is absent, not regular, or a symlink'
    install -o root -g root -m 0700 "$installer_file" \
      "$evidence_dir/nix-installer"
  else
    curl --fail --silent --show-error --location \
      --proto '=https' --tlsv1.2 --retry 2 --max-time 120 \
      --output "$evidence_dir/nix-installer" "$installer_url"
  fi
  chmod 0700 "$evidence_dir/nix-installer"
  [[ "$(sha256sum "$evidence_dir/nix-installer" | awk '{print $1}')" == "$installer_sha256" ]] ||
    fail 'downloaded installer checksum differs from the repository pin'
  [[ "$(stat -c %s "$evidence_dir/nix-installer")" == "$installer_size" ]] ||
    fail 'downloaded installer size differs from the repository pin'
  [[ "$("$evidence_dir/nix-installer" --version | awk '{print $NF}')" == "$installer_version" ]] ||
    fail 'downloaded installer version differs from the repository pin'

  "$evidence_dir/nix-installer" plan \
    --out-file "$evidence_dir/install-plan.json" linux \
    --nix-build-group-name "$group_name" \
    --nix-build-group-id "$group_id" \
    --nix-build-user-prefix "$user_prefix" \
    --nix-build-user-count "$user_count" \
    --nix-build-user-id-base "$user_id_base" \
    --enable-flakes \
    --init systemd
  chmod 0600 "$evidence_dir/install-plan.json"
  plan_flakes="$(
    python3 - "$evidence_dir/install-plan.json" "$source_file" <<'PY'
import json
import sys

plan_path, source_path = sys.argv[1:]
with open(plan_path, encoding="utf-8") as handle:
    plan = json.load(handle)
with open(source_path, encoding="utf-8") as handle:
    source = json.load(handle)
expected = source["linuxPlanner"]
planner = plan.get("planner", {})
settings = planner.get("settings", {})
init = planner.get("init", {})
checks = {
    "installer_version": plan.get("version") == source["installer"]["version"],
    "planner": planner.get("planner") == "linux",
    "init": init.get("init") == "Systemd",
    "start_daemon": init.get("start_daemon") is expected["startDaemon"],
    "modify_profile": settings.get("modify_profile") is expected["modifyProfile"],
    "group_name": settings.get("nix_build_group_name") == expected["buildGroupName"],
    "group_id": settings.get("nix_build_group_id") == expected["buildGroupId"],
    "user_prefix": settings.get("nix_build_user_prefix") == expected["buildUserPrefix"],
    "user_count": settings.get("nix_build_user_count") == expected["buildUserCount"],
    "user_id_base": settings.get("nix_build_user_id_base") == expected["buildUserIdBase"],
    "flakes": settings.get("enable_flakes") is expected["enableFlakes"],
    "no_channel": settings.get("add_channel") is expected["addChannel"],
    "default_tls": settings.get("ssl_cert_file") is None,
    "no_extra_conf": settings.get("extra_conf") == [],
    "not_forced": settings.get("force") is False,
    "nix_conf_owned": settings.get("skip_nix_conf") is False,
}

action_names = set()
managed_paths = set()

def visit(value):
    if isinstance(value, dict):
        action_name = value.get("action_name")
        if isinstance(action_name, str):
            action_names.add(action_name)
        for key, item in value.items():
            if key in {"path", "dest", "service_dest"} and isinstance(item, str) and item.startswith("/"):
                managed_paths.add(item)
            visit(item)
    elif isinstance(value, list):
        for item in value:
            visit(item)

visit(plan.get("actions", []))
expected_actions = {
    "add_user_to_group",
    "configure_init_service",
    "configure_nix",
    "configure_shell_profile",
    "create_directory",
    "create_group",
    "create_nix_tree",
    "create_or_insert_into_file",
    "create_or_merge_nix_config",
    "create_upstream_init_service",
    "create_user",
    "create_users_and_group",
    "fetch_and_unpack_nix",
    "mount_unpacked_nix",
    "place_nix_configuration",
    "provision_nix",
    "remove_directory",
    "setup_default_profile",
}
if action_names != expected_actions:
    checks["exact_action_types"] = False

def allowed_path(path):
    prefixes = (
        "/nix",
        "/etc/nix",
        "/etc/fish",
        "/usr/local/etc/fish",
        "/usr/share/fish",
        "/usr/local/share/fish",
    )
    exact = {
        "/etc/bashrc",
        "/etc/bash.bashrc",
        "/etc/zsh",
        "/etc/zshrc",
        "/etc/zsh/zshrc",
        "/etc/profile.d/nix.sh",
        "/etc/tmpfiles.d",
        "/etc/tmpfiles.d/nix-daemon.conf",
        "/etc/systemd/system/nix-daemon.service",
        "/etc/systemd/system/nix-daemon.socket",
    }
    return path in exact or any(path == prefix or path.startswith(prefix + "/") for prefix in prefixes)

if not managed_paths or any(not allowed_path(path) for path in managed_paths):
    checks["exact_managed_paths"] = False
failed = [name for name, passed in checks.items() if not passed]
if failed:
    raise SystemExit("install plan mismatch: " + ",".join(failed))
print("true")
PY
  )"
  [[ "$plan_flakes" == true ]] || fail 'generated install plan did not pass policy'

  (
    cd "$evidence_dir"
    sha256sum context.txt gpu.before.txt hosts.json install-plan.json \
      nix-installer protected-units.before.tsv rollback.sh source.json \
      rollback-files.before.tsv tailscale.before.txt >SHA256SUMS
  )
  chmod 0600 "$evidence_dir/SHA256SUMS"
  touch "$evidence_dir/ARMED"
  timer_unit="dgx-nix-bootstrap-rollback-$stamp.timer"
  service_unit="dgx-nix-bootstrap-rollback-$stamp.service"
  systemd-run --unit="${timer_unit%.timer}" --on-active=15m \
    --timer-property=AccuracySec=1s \
    "$evidence_dir/rollback.sh" "$evidence_dir" >/dev/null
  systemctl is-active --quiet "$timer_unit" || fail 'bootstrap rollback timer did not arm'
  printf 'PASS|rollback|%s armed before installation\n' "$timer_unit"

  if ! "$evidence_dir/nix-installer" install --no-confirm \
    "$evidence_dir/install-plan.json"; then
    fail "official installation failed; $timer_unit remains armed"
  fi

  [[ -x "$nix_bin" && -r /nix/receipt.json ]] ||
    fail "installation is incomplete; $timer_unit remains armed"
  [[ "$(sha256sum /nix/nix-installer | awk '{print $1}')" == "$installer_sha256" ]] ||
    fail "installed provisioning artifact changed; $timer_unit remains armed"
  [[ "$(receipt_matches_base)" == true ]] ||
    fail "installed receipt differs from the exact plan; $timer_unit remains armed"
  features="$($nix_bin config show experimental-features)"
  [[ " $features " == *' nix-command '* && " $features " == *' flakes '* ]] ||
    fail "persistent Nix features differ from the plan; $timer_unit remains armed"

  observed_runtime="$($nix_bin --version | awk '{print $NF}')"
  if [[ "$observed_runtime" != "$desired_runtime" ]]; then
    "$nix_bin" --extra-experimental-features 'nix-command flakes' \
      upgrade-nix \
      --profile /nix/var/nix/profiles/default \
      --refresh \
      --nix-store-paths-url "file://$repo_dir/root/nix/store-paths.nix"
    systemctl daemon-reload
    systemctl restart nix-daemon.service
  fi

  if [[ "${DGX_NIX_BOOTSTRAP_TEST_FAIL_AFTER_RUNTIME:-0}" == 1 ]]; then
    fail "injected post-runtime failure; $timer_unit remains armed"
  fi

  observed_runtime="$($nix_bin --version | awk '{print $NF}')"
  [[ "$observed_runtime" == "$desired_runtime" ]] ||
    fail "runtime is $observed_runtime after upgrade; $timer_unit remains armed"
  systemctl is-active --quiet nix-daemon.socket ||
    systemctl is-active --quiet nix-daemon.service ||
    fail "Nix daemon is unavailable; $timer_unit remains armed"
  "$nix_bin" store info >/dev/null 2>&1
  [[ "$(systemctl is-system-running)" == running ]] ||
    fail "systemd is not healthy; $timer_unit remains armed"
  capture_protected_units >"$evidence_dir/protected-units.after.tsv"
  capture_gpu >"$evidence_dir/gpu.after.txt"
  capture_tailscale >"$evidence_dir/tailscale.after.txt"
  chmod 0600 "$evidence_dir/protected-units.after.tsv" \
    "$evidence_dir/gpu.after.txt" "$evidence_dir/tailscale.after.txt"
  cmp -s "$evidence_dir/protected-units.before.tsv" \
    "$evidence_dir/protected-units.after.tsv" ||
    fail "a protected service changed; $timer_unit remains armed"
  cmp -s "$evidence_dir/gpu.before.txt" "$evidence_dir/gpu.after.txt" ||
    fail "GPU identity or driver changed; $timer_unit remains armed"
  cmp -s "$evidence_dir/tailscale.before.txt" "$evidence_dir/tailscale.after.txt" ||
    fail "Tailscale/SSH state changed; $timer_unit remains armed"

  systemctl stop "$timer_unit"
  systemctl reset-failed "$timer_unit" "$service_unit" 2>/dev/null || true
  rm -f -- "$evidence_dir/ARMED"
  touch "$evidence_dir/COMPLETE"
  printf 'PASS|nix_bootstrap|installed exact installer %s and runtime %s\n' \
    "$installer_version" "$observed_runtime"
  printf '%s\n' 'PASS|continuity|systemd, GPU, and existing factory/access services stayed exact'
  printf 'PASS|rollback|%s disarmed after complete postflight\n' "$timer_unit"
  printf 'EVIDENCE_DIR=%s\n' "$evidence_dir"
  printf '%s\n' 'BOOTSTRAP_STATUS=INSTALLED'
}

target_host=${1:-$(hostname -s)}
[[ "$target_host" == "$(hostname -s)" ]] || fail 'bootstrap can target only the local host'
declared_user="$(json_value "$fleet_file" "hosts.$target_host.users.armen.unixName" 2>/dev/null)" ||
  fail 'host is not declared in fleet/hosts.json'
declared_home="$(json_value "$fleet_file" "hosts.$target_host.users.armen.homeDirectory")"
[[ "$(id -un)" == "$declared_user" || "$EUID" -eq 0 ]] ||
  fail 'current user does not match the declared managed user'
[[ "$(uname -m)" == aarch64 ]] || fail 'bootstrap supports only aarch64 hosts'

if [[ "$EUID" -eq 0 ]]; then
  [[ "${2:-}" == --root-install && -n "${3:-}" && -n "${4:-}" ]] ||
    fail 'root mode is internal; invoke scripts/dgx-setup bootstrap as the managed user'
  root_install "$target_host" "$3" "$4"
  exit
fi

[[ "$HOME" == "$declared_home" ]] || fail 'HOME does not match the declared user mapping'
if [[ -e /nix || -e /etc/nix ]]; then
  verify_existing
  exit
fi
surface_is_clean || fail 'partial or foreign Nix surface exists; refusing overwrite'
[[ -z "$(git -C "$repo_dir" status --porcelain=v1)" ]] ||
  fail 'commit the declared host selection before bootstrap'
for command_name in cmp curl getent git install nvidia-smi python3 sha256sum \
  stat sudo systemctl timeout; do
  command -v "$command_name" >/dev/null 2>&1 ||
    fail "required factory command is missing: $command_name"
done

"$repo_dir/scripts/update-nix-installer.sh" --check
expected_commit="$(git -C "$repo_dir" rev-parse HEAD)"
printf 'INFO|nix_bootstrap|clean host; installing pinned Nix and desired runtime from %s\n' \
  "$expected_commit"
sudo "$repo_dir/scripts/bootstrap-nix.sh" "$target_host" --root-install \
  "$expected_commit" "$declared_user"
