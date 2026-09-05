#!/usr/bin/env bash
set -uo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  printf '%s\n' \
    'Run this isolated test as root: sudo ./scripts/test-tailscale-unit-lifecycle.sh' >&2
  exit 1
fi

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir" || exit 1

nix_bin=/nix/var/nix/profiles/default/bin/nix
vendor_unit=/usr/lib/systemd/system/tailscaled.service
vendor_wants=/etc/systemd/system/multi-user.target.wants/tailscaled.service
managed_unit=/etc/systemd/system/tailscaled.service
managed_wants=/etc/systemd/system/system-manager.target.wants/tailscaled.service

die() {
  printf 'FAIL|tailscale_unit_test|%s\n' "$*" >&2
  exit 1
}

eval_output() {
  "$nix_bin" \
    --extra-experimental-features "nix-command flakes" \
    eval --raw --no-write-lock-file "$1"
}

[[ -x "$nix_bin" ]] || die "missing root-profile Nix at $nix_bin"

generation_one="$(eval_output .#packages.aarch64-linux.root-system-canary.outPath)" || exit 1
generation_two="$(eval_output .#packages.aarch64-linux.root-system-canary-generation-two.outPath)" || exit 1
generation_three="$(eval_output .#packages.aarch64-linux.root-system-canary-generation-three-boot.outPath)" || exit 1
candidate="$(eval_output .#packages.aarch64-linux.root-system-tailscale-migration.outPath)" || exit 1
generation_five="$(eval_output .#packages.aarch64-linux.root-system-desktop-headless.outPath)" || exit 1

assert_host_boundary() {
  local current fragment retained_status

  current="$(readlink -f -- /nix/var/nix/profiles/system-manager-profiles/system-manager 2>/dev/null || true)"
  systemctl is-active --quiet tailscaled.service || die "live tailscaled.service is not active"
  fragment="$(systemctl show tailscaled.service -p FragmentPath --value)"
  if [[ "$current" == "$generation_three" ]]; then
    "$repo_dir/scripts/root-tailscale-migration-transaction.sh" \
      verify-before "$generation_one" "$generation_two" \
      "$generation_three" "$candidate" >/dev/null ||
      die "generation-three/vendor host boundary failed verification"
    [[ "$fragment" == "$vendor_unit" ]] ||
      die "live Tailscale is not loaded from the vendor unit: $fragment"
    [[ -L "$vendor_wants" && "$(readlink -f -- "$vendor_wants")" == "$vendor_unit" ]] ||
      die "vendor Tailscale boot link is absent or changed"
    for path in "$managed_unit" "$managed_wants"; do
      [[ ! -e "$path" && ! -L "$path" ]] ||
        die "candidate ownership path already exists on host: $path"
    done
  elif [[ "$current" == "$candidate" ]]; then
    "$repo_dir/scripts/root-tailscale-migration-transaction.sh" \
      verify-after "$generation_one" "$generation_two" \
      "$generation_three" "$candidate" >/dev/null ||
      die "generation-four/Nix-managed host boundary failed verification"
    [[ "$fragment" == "$managed_unit" ]] ||
      die "live Tailscale is not loaded from the Nix-managed unit: $fragment"
  elif [[ "$current" == "$generation_five" ]]; then
    retained_status="$("$repo_dir/scripts/dgx-tailscale" status 2>&1)" ||
      die "generation-five/Nix-managed host boundary failed verification: $retained_status"
    grep -Fx 'MIGRATION_STATUS=CONFIRMED_NIX_OWNED' <<<"$retained_status" >/dev/null ||
      die "generation-five Tailscale ownership is not confirmed"
    [[ "$fragment" == "$managed_unit" ]] ||
      die "live Tailscale is not loaded from the Nix-managed unit: $fragment"
  else
    die "live System Manager generation is not a supported Tailscale boundary: ${current:-ABSENT}"
  fi
}

assert_host_boundary

service_before="$(
  systemctl show tailscaled.service \
    -p ActiveState -p SubState -p MainPID \
    -p ExecMainStartTimestampMonotonic -p FragmentPath -p NeedDaemonReload
)"

printf 'INFO|candidate|%s\n' "$candidate"
printf '%s\n' \
  'INFO|disposable_test|apt-to-Nix ownership, two reboots, and rollback run only inside the container'

export NIX_USER_CONF_FILES=/dev/null
"$nix_bin" \
  --store local \
  --extra-experimental-features \
  "nix-command flakes auto-allocate-uids cgroups" \
  --option auto-allocate-uids true \
  build --no-link --no-write-lock-file \
  .#checks.aarch64-linux.tailscale-unit-lifecycle-container
build_status=$?

assert_host_boundary

service_after="$(
  systemctl show tailscaled.service \
    -p ActiveState -p SubState -p MainPID \
    -p ExecMainStartTimestampMonotonic -p FragmentPath -p NeedDaemonReload
)"
[[ "$service_after" == "$service_before" ]] ||
  die "live tailscaled.service changed while the disposable test ran"

if [[ "$build_status" -eq 0 ]]; then
  printf '%s\n' \
    'PASS|tailscale_unit_lifecycle|container handoff/reboot/rollback passed; live host stayed exact'
fi

exit "$build_status"
