#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'FAIL|fresh_nix_rollback|%s\n' "$1" >&2
  exit 1
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

manifest_records_absent() {
  local path=$1
  awk -F '\t' -v expected_path="$path" '
    $1 == "ABSENT" && $2 == expected_path { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$evidence_dir/rollback-files.before.tsv"
}

preserve_absent_path_residual() {
  local path=$1 evidence_name=$2 residual_dir destination kind target

  manifest_records_absent "$path" ||
    fail "$path was not recorded absent before bootstrap"
  [[ -e "$path" || -L "$path" ]] || return 0

  residual_dir="$evidence_dir/installer-residuals"
  destination="$residual_dir/$evidence_name"
  install -d -o root -g root -m 0700 "$residual_dir"
  [[ ! -e "$destination" && ! -L "$destination" ]] ||
    fail "preserved residual destination already exists for $path"
  kind="$(stat -c %F "$path")"
  target=-
  [[ -L "$path" ]] && target="$(readlink "$path")"
  printf '%s\t%s\t%s\t%s\n' "$path" "$destination" "$kind" "$target" \
    >>"$residual_dir/manifest.tsv"
  chmod 0600 "$residual_dir/manifest.tsv"
  mv -- "$path" "$destination"
  printf 'INFO|fresh_nix_rollback|preserved installer residual %s at %s\n' \
    "$path" "$destination"
}

preserve_installer_residuals() {
  # nix-installer 2.35.1 delegates default-profile creation to nix-env, but
  # SetupDefaultProfile::revert only unsets NIX_SSL_CERT_FILE. The official
  # receipt uninstall can therefore leave root compatibility/cache paths.
  # Their signed pre-state is ABSENT; move any residual into private rollback
  # evidence instead of deleting it, restoring the boundary recoverably.
  preserve_absent_path_residual /root/.nix-profile root-nix-profile
  preserve_absent_path_residual /root/.nix-defexpr root-nix-defexpr
  preserve_absent_path_residual /root/.nix-channels root-nix-channels
  preserve_absent_path_residual /root/.local/state/nix root-local-state-nix
  preserve_absent_path_residual /root/.cache/nix root-cache-nix
}

[[ "$EUID" -eq 0 ]] || fail 'must run as root'
[[ "$#" -eq 1 ]] || fail 'expected one evidence-directory argument'

evidence_dir=$1
case "$evidence_dir" in
  /var/lib/dgx-setup/nix-bootstrap/*)
    ;;
  *)
    fail 'evidence directory is outside the bootstrap state root'
    ;;
esac

[[ -d "$evidence_dir" && ! -L "$evidence_dir" ]] ||
  fail 'evidence directory is absent or a symlink'
[[ "$(stat -c '%U:%G:%a' "$evidence_dir")" == root:root:700 ]] ||
  fail 'evidence directory ownership or mode changed'
[[ -f "$evidence_dir/ARMED" && ! -L "$evidence_dir/ARMED" ]] || exit 0
[[ -x "$evidence_dir/nix-installer" && ! -L "$evidence_dir/nix-installer" ]] ||
  fail 'retained installer is unavailable'
(cd "$evidence_dir" && sha256sum -c SHA256SUMS >/dev/null) ||
  fail 'bootstrap evidence checksum verification failed'

expected_sha256="$(awk '$2 == "nix-installer" { print $1 }' "$evidence_dir/SHA256SUMS")"
observed_sha256="$(sha256sum "$evidence_dir/nix-installer" | awk '{print $1}')"
[[ -n "$expected_sha256" && "$observed_sha256" == "$expected_sha256" ]] ||
  fail 'retained installer checksum changed'

if [[ -r /nix/receipt.json ]]; then
  printf '%s\n' 'INFO|fresh_nix_rollback|running official receipt-driven uninstall'
  "$evidence_dir/nix-installer" uninstall --no-confirm /nix/receipt.json
elif [[ -e /nix || -e /etc/nix ]]; then
  fail 'partial Nix surface has no receipt; refusing manual deletion'
fi

preserve_installer_residuals

if [[ -e /nix || -e /etc/nix ||
      -e /etc/systemd/system/nix-daemon.service ||
      -L /etc/systemd/system/nix-daemon.service ||
      -e /etc/systemd/system/nix-daemon.socket ||
      -L /etc/systemd/system/nix-daemon.socket ||
      -e /etc/systemd/system/multi-user.target.wants/nix-daemon.service ||
      -L /etc/systemd/system/multi-user.target.wants/nix-daemon.service ||
      -e /etc/systemd/system/sockets.target.wants/nix-daemon.socket ||
      -L /etc/systemd/system/sockets.target.wants/nix-daemon.socket ||
      -e /etc/tmpfiles.d/nix-daemon.conf ||
      -L /etc/tmpfiles.d/nix-daemon.conf ]]; then
  fail 'official uninstall left a Nix surface; preserve evidence for review'
fi

while IFS=$'\t' read -r state path expected; do
  case "$state" in
    SHA256)
      [[ -f "$path" && "$(sha256sum "$path" | awk '{print $1}')" == "$expected" ]] ||
        fail "official uninstall did not restore $path"
      ;;
    ABSENT)
      [[ ! -e "$path" && ! -L "$path" ]] ||
        fail "official uninstall did not remove newly created $path"
      ;;
    *)
      fail 'invalid rollback-file manifest entry'
      ;;
  esac
done <"$evidence_dir/rollback-files.before.tsv"

getent group nixbld >/dev/null && fail 'official uninstall left the nixbld group'
for index in $(seq 1 32); do
  getent passwd "nixbld$index" >/dev/null &&
    fail "official uninstall left nixbld$index"
done

[[ "$(systemctl is-system-running)" == running ]] ||
  fail 'systemd is not healthy after rollback'
cmp -s "$evidence_dir/protected-units.before.tsv" <(capture_protected_units) ||
  fail 'a protected service changed across bootstrap rollback'
cmp -s "$evidence_dir/gpu.before.txt" \
  <(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader,nounits) ||
  fail 'GPU identity or driver changed across bootstrap rollback'
cmp -s "$evidence_dir/tailscale.before.txt" <(capture_tailscale) ||
  fail 'Tailscale/SSH state changed across bootstrap rollback'

rm -f -- "$evidence_dir/ARMED"
touch "$evidence_dir/ROLLED_BACK"
printf '%s\n' 'PASS|fresh_nix_rollback|official uninstall restored the clean bootstrap boundary'
