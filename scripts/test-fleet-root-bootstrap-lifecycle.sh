#!/usr/bin/env bash
set -uo pipefail

# Runs the complete pristine -> managed factory -> headless lifecycle only in
# System Manager's disposable container.  The live host is byte/symlink/service
# snapshotted before and after and is never activated, registered, or rebooted.

if [[ "$EUID" -ne 0 ]]; then
  printf '%s\n' \
    'Run this isolated test as root: sudo ./scripts/test-fleet-root-bootstrap-lifecycle.sh' >&2
  exit 1
fi

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir" || exit 1
nix_bin=/nix/var/nix/profiles/default/bin/nix

die() {
  printf 'FAIL|fleet_root_bootstrap_test|%s\n' "$*" >&2
  exit 1
}

capture_paths() {
  local path

  for path in \
    /etc/dgx-setup/canary \
    /etc/dgx-setup/desktop-mode \
    /etc/systemd/system/default.target \
    /etc/systemd/system/default.target.wants/system-manager.target \
    /etc/systemd/system/dgx-headless.target \
    /etc/systemd/system/dgx-gnome.target \
    /etc/systemd/system/dgx-setup-canary.service \
    /etc/systemd/system/sysinit-reactivation.target \
    /etc/systemd/system/system-manager.target \
    /etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service \
    /etc/systemd/system/system-manager.target.wants/tailscaled.service \
    /etc/systemd/system/tailscaled.service \
    /nix/var/nix/gcroots/system-manager-current \
    /nix/var/nix/gcroots/dgx-setup-fleet-factory \
    /nix/var/nix/gcroots/dgx-setup-fleet-headless \
    /nix/var/nix/gcroots/dgx-setup-fleet-bootstrap-rollback \
    /var/lib/dgx-setup/fleet-bootstrap; do
    if [[ -L "$path" ]]; then
      printf 'LINK|%s|%s\n' "$path" "$(readlink -- "$path")"
    elif [[ -f "$path" ]]; then
      printf 'FILE|%s|%s\n' "$path" "$(sha256sum "$path" | awk '{print $1}')"
    elif [[ -d "$path" ]]; then
      printf 'DIR|%s\n' "$path"
      find "$path" -mindepth 1 -maxdepth 2 -printf '%y|%P|%l\n' | sort
    else
      printf 'ABSENT|%s\n' "$path"
    fi
  done
  if [[ -d /nix/var/nix/profiles/system-manager-profiles ]]; then
    find /nix/var/nix/profiles/system-manager-profiles \
      -mindepth 1 -maxdepth 1 -printf 'PROFILE|%f|%l\n' | sort
  else
    printf 'PROFILE|ABSENT\n'
  fi
  if [[ -f /var/lib/system-manager/state/system-manager-state.json ]]; then
    sha256sum /var/lib/system-manager/state/system-manager-state.json
  else
    printf 'STATE|ABSENT\n'
  fi
}

capture_units() {
  local unit
  for unit in tailscaled.service gdm.service docker.service \
    dgx-dashboard.service dgx-dashboard-admin.service nvidia-persistenced.service; do
    systemctl show "$unit" \
      -p Id -p LoadState -p ActiveState -p SubState -p MainPID \
      -p ExecMainStartTimestampMonotonic -p FragmentPath -p NeedDaemonReload
  done
}

[[ -x "$nix_bin" ]] || die "missing root-profile Nix at $nix_bin"
[[ -z "$(git status --porcelain=v1)" ]] ||
  die 'repository must be clean so the test binds one committed design'

paths_before="$(capture_paths)" || exit 1
units_before="$(capture_units)" || exit 1
protected_before="$(sha256sum /etc/nix/nix.conf /etc/passwd /etc/group /etc/shadow)" || exit 1

printf '%s\n' \
  'INFO|disposable_test|optional Tailscale, pristine rollback, two guarded transitions, and three reboots run only inside the container'

export NIX_USER_CONF_FILES=/dev/null
"$nix_bin" \
  --store local \
  --extra-experimental-features \
  "nix-command flakes auto-allocate-uids cgroups" \
  --option auto-allocate-uids true \
  build --no-link --no-write-lock-file \
  .#checks.aarch64-linux.fleet-root-bootstrap-lifecycle-container
build_status=$?

paths_after="$(capture_paths)" || exit 1
units_after="$(capture_units)" || exit 1
protected_after="$(sha256sum /etc/nix/nix.conf /etc/passwd /etc/group /etc/shadow)" || exit 1
[[ "$paths_after" == "$paths_before" ]] || die 'live root state changed during disposable test'
[[ "$units_after" == "$units_before" ]] || die 'a live protected service changed during disposable test'
[[ "$protected_after" == "$protected_before" ]] || die 'a protected host file changed during disposable test'

if ((build_status == 0)); then
  printf '%s\n' \
    'PASS|fleet_root_bootstrap_lifecycle|optional access, pristine install, reboot recovery, headless switch, and host non-mutation passed'
fi
exit "$build_status"
