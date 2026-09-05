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
transaction="$repo_dir/scripts/root-tailscale-migration-transaction.sh"
controller_paths=(
  /etc/dgx-setup/desktop-mode
  /etc/systemd/system/default.target
  /etc/systemd/system/dgx-headless.target
  /etc/systemd/system/dgx-gnome.target
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

assert_host_boundary() {
  local current default_target path unit

  current="$(readlink -f -- \
    /nix/var/nix/profiles/system-manager-profiles/system-manager \
    2>/dev/null || true)"
  [[ "$current" == "$generation_four" ]] ||
    die "live System Manager generation is not exact generation four: ${current:-ABSENT}"

  "$transaction" verify-after \
    "$generation_one" "$generation_two" "$generation_three" \
    "$generation_four" >/dev/null ||
    die 'live Nix-managed Tailscale boundary failed verification'

  default_target="$(systemctl get-default 2>/dev/null || true)"
  [[ "$default_target" == graphical.target ]] ||
    die "factory default target is not graphical.target: ${default_target:-UNKNOWN}"

  for path in "${controller_paths[@]}"; do
    [[ ! -e "$path" && ! -L "$path" ]] ||
      die "desktop-controller path already exists on the live host: $path"
  done

  for unit in dgx-headless.target dgx-gnome.target; do
    [[ "$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)" == not-found ]] ||
      die "desktop-controller unit is unexpectedly loaded on the live host: $unit"
  done

  systemctl is-active --quiet gdm.service || die 'factory GDM is not active'
  systemctl is-active --quiet tailscaled.service || die 'Nix-managed Tailscale is not active'
  [[ "$(systemctl is-system-running 2>/dev/null || true)" == running ]] ||
    die 'systemd is not running cleanly'
  [[ -z "$(systemctl list-units --state=failed --plain --no-legend)" ]] ||
    die 'the live host has failed units'
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

generation_one="$(eval_output .#packages.aarch64-linux.root-system-canary.outPath)" || exit 1
generation_two="$(eval_output .#packages.aarch64-linux.root-system-canary-generation-two.outPath)" || exit 1
generation_three="$(eval_output .#packages.aarch64-linux.root-system-canary-generation-three-boot.outPath)" || exit 1
generation_four="$(eval_output .#packages.aarch64-linux.root-system-tailscale-migration.outPath)" || exit 1
headless_candidate="$(eval_output .#packages.aarch64-linux.root-system-desktop-headless.outPath)" || exit 1
gnome_candidate="$(eval_output .#packages.aarch64-linux.root-system-desktop-gnome.outPath)" || exit 1

assert_host_boundary
services_before="$(unit_snapshot)" || exit 1

printf 'INFO|live_generation|%s\n' "$generation_four"
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
