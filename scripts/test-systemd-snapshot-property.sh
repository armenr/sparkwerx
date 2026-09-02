#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
parser="$repo_dir/scripts/systemd-snapshot-property.sh"

fail() {
  printf 'FAIL|%s\n' "$1" >&2
  exit 1
}

[[ -x "$parser" ]] || fail "parser is missing or not executable"
bash -n "$parser" || fail "parser failed syntax validation"

temp_dir="$(mktemp -d)"
fixture="$temp_dir/services.before.txt"
cleanup() {
  rm -f -- "$fixture"
  rmdir -- "$temp_dir"
}
trap cleanup EXIT

printf '%s\n' \
  'MainPID=101' \
  'FragmentPath=/usr/lib/systemd/system/nix-daemon.service' \
  'Id=nix-daemon.service' \
  'ActiveEnterTimestampMonotonic=1001' \
  '' \
  'ActiveEnterTimestampMonotonic=2002' \
  'Id=tailscaled.service' \
  'MainPID=202' \
  'FragmentPath=/usr/lib/systemd/system/tailscaled.service' \
  '' \
  'MainPID=' \
  'Id=empty.service' \
  'FragmentPath=/run/systemd/transient/empty.service' \
  >"$fixture"

[[ "$($parser "$fixture" nix-daemon.service MainPID)" == 101 ]] ||
  fail "property preceding Id was not associated with nix-daemon.service"
[[ "$($parser "$fixture" tailscaled.service ActiveEnterTimestampMonotonic)" == 2002 ]] ||
  fail "property preceding Id was not associated with tailscaled.service"
[[ "$($parser "$fixture" tailscaled.service MainPID)" == 202 ]] ||
  fail "property following Id was not associated with tailscaled.service"
[[ "$($parser "$fixture" nix-daemon.service FragmentPath)" == \
  /usr/lib/systemd/system/nix-daemon.service ]] ||
  fail "nix-daemon fragment path leaked across records"
[[ "$($parser "$fixture" empty.service MainPID)" == "" ]] ||
  fail "present empty property was not returned as an empty result"
if "$parser" "$fixture" missing.service MainPID >/dev/null 2>&1; then
  fail "missing unit unexpectedly returned success"
fi
if "$parser" "$fixture" empty.service ActiveState >/dev/null 2>&1; then
  fail "missing property unexpectedly returned success"
fi
if "$parser" "$fixture" nix-daemon.service 'MainPID;bad' >/dev/null 2>&1; then
  fail "invalid property name unexpectedly returned success"
fi

printf '%s\n' \
  'PASS|systemd_snapshot_property|whole-record parser preserves property/unit association'
