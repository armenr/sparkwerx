#!/usr/bin/env bash
set -uo pipefail

if [[ "$EUID" -ne 0 ]]; then
  printf '%s\n' \
    'Run this isolated test as root: sudo ./scripts/test-desktop-mode-lifecycle.sh' >&2
  exit 1
fi

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir" || exit 1

nix_bin=/nix/var/nix/profiles/default/bin/nix
headless_root=/nix/var/nix/gcroots/dgx-setup-desktop-headless-pilot
profile_five=/nix/var/nix/profiles/system-manager-profiles/system-manager-5-link
guard_paths=(
  /var/lib/dgx-setup/desktop-switch
  /nix/var/nix/gcroots/dgx-setup-desktop-switch-rollback
  /etc/systemd/system/dgx-desktop-switch-rollback.service
  /etc/systemd/system/dgx-desktop-switch-rollback.timer
  /etc/systemd/system/timers.target.wants/dgx-desktop-switch-rollback.timer
)
protected_units=(
  tailscaled.service
  gdm.service
  docker.service
  dgx-dashboard.service
  dgx-dashboard-admin.service
  nvidia-persistenced.service
)

die() {
  printf 'FAIL|desktop_mode_test|%s\n' "$*" >&2
  exit 1
}

eval_output() {
  "$nix_bin" \
    --extra-experimental-features "nix-command flakes" \
    eval --raw --no-write-lock-file "$1"
}

path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

assert_host_boundary() {
  local current desktop_status path

  current="$(readlink -f -- \
    /nix/var/nix/profiles/system-manager-profiles/system-manager \
    2>/dev/null || true)"
  [[ "$current" == "$headless_candidate" ]] ||
    die "live System Manager generation is not exact generation five: ${current:-ABSENT}"
  [[ -L "$profile_five" && "$(readlink -- "$profile_five")" == "$headless_candidate" ]] ||
    die 'System Manager generation-five profile link changed'
  [[ -L "$headless_root" && "$(readlink -- "$headless_root")" == "$headless_candidate" ]] ||
    die 'headless generation-five pilot root changed'
  for path in "${guard_paths[@]}"; do
    ! path_exists "$path" || die "unexpected desktop-switch guard exists: $path"
  done
  desktop_status="$("$repo_dir/scripts/dgx-desktop" status 2>&1)" ||
    die "live headless boundary failed verification: $desktop_status"
  grep -Fx 'DESKTOP_STATUS=HEADLESS_CONFIRMED' <<<"$desktop_status" >/dev/null ||
    die 'live desktop is not confirmed generation-five headless'
}

unit_snapshot() {
  local unit
  for unit in "${protected_units[@]}"; do
    systemctl show "$unit" \
      -p Id -p LoadState -p ActiveState -p SubState -p MainPID \
      -p ExecMainStartTimestampMonotonic -p FragmentPath -p NeedDaemonReload
  done
}

[[ -x "$nix_bin" ]] || die "missing root-profile Nix at $nix_bin"
[[ -z "$(git status --porcelain=v1)" ]] ||
  die 'repository must be clean so the test binds one committed design'

generation_four="$(eval_output .#packages.aarch64-linux.root-system-tailscale-migration.outPath)" || exit 1
headless_candidate="$(eval_output .#packages.aarch64-linux.root-system-desktop-headless.outPath)" || exit 1
gnome_candidate="$(eval_output .#packages.aarch64-linux.root-system-desktop-gnome.outPath)" || exit 1

assert_host_boundary
services_before="$(unit_snapshot)" || exit 1

printf 'INFO|live_generation|%s\n' "$headless_candidate"
printf 'INFO|container_fixture_generation|%s\n' "$generation_four"
printf 'INFO|headless_candidate|%s\n' "$headless_candidate"
printf 'INFO|gnome_candidate|%s\n' "$gnome_candidate"
printf '%s\n' \
  'INFO|disposable_test|headless/GNOME isolates, three reboots, and factory fallback run only inside the container'

export NIX_USER_CONF_FILES=/dev/null
"$nix_bin" \
  --store local \
  --extra-experimental-features \
  "nix-command flakes auto-allocate-uids cgroups" \
  --option auto-allocate-uids true \
  build --no-link --no-write-lock-file \
  .#checks.aarch64-linux.desktop-mode-lifecycle-container
build_status=$?

assert_host_boundary
services_after="$(unit_snapshot)" || exit 1
[[ "$services_after" == "$services_before" ]] ||
  die 'a protected live-host service changed while the disposable test ran'

if [[ "$build_status" -eq 0 ]]; then
  printf '%s\n' \
    'PASS|desktop_mode_lifecycle|headless/GNOME persistence, access continuity, reversibility, and factory fallback passed; live host stayed exact'
fi

exit "$build_status"
