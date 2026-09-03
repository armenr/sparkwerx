#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
operator=$repo_dir/scripts/dgx-home
nix_bin=/nix/var/nix/profiles/default/bin/nix
nix_env=/nix/var/nix/profiles/default/bin/nix-env

fail() {
  printf 'FAIL|dgx_home_rollback_test|%s\n' "$1" >&2
  exit 1
}

temp_dir="$(mktemp -d --tmpdir dgx-home-test.XXXXXXXX)"
cleanup() {
  rm -rf -- "$temp_dir"
}
trap cleanup EXIT

home=$temp_dir/home
snapshot=$temp_dir/snapshot
profiles=$home/.local/state/nix/profiles
candidate="$($nix_bin --extra-experimental-features 'nix-command flakes' \
  eval --raw '.#homeConfigurations."n0b0dy@sparkle-01".activationPackage')"
$nix_bin --extra-experimental-features 'nix-command flakes' build --no-link \
  '.#checks.aarch64-linux.home-sparkle-01'
home_path="$(readlink -e "$candidate/home-path")"
home_files="$(readlink -e "$candidate/home-files")"
unit=dgx-home-headless-rollback-test-never-armed

mkdir -p -- \
  "$home/.cache" \
  "$home/.codex" \
  "$home/.local/bin" \
  "$home/.local/state/home-manager/gcroots" \
  "$profiles" \
  "$snapshot/backup"
chmod 0700 -- "$snapshot"

printf 'model = "preserve-me"\n' >"$snapshot/backup/codex_config"
cp -p -- "$snapshot/backup/codex_config" "$snapshot/codex-config.expected"
"$repo_dir/scripts/reconcile-codex-relaxed-defaults.sh" \
  --apply "$snapshot/codex-config.expected" >/dev/null
cp -p -- "$snapshot/codex-config.expected" "$home/.codex/config.toml"

ln -s -- "$home_files/.local/bin/codex" "$home/.local/bin/codex"
ln -s -- "$home_files/.cache/.keep" "$home/.cache/.keep"
ln -s -- "$home_files/.local/state/.keep" "$home/.local/state/.keep"
ln -s -- home-manager-1-link "$profiles/home-manager"
ln -s -- "$candidate" "$profiles/home-manager-1-link"
ln -s -- "$candidate" "$home/.local/state/home-manager/gcroots/current-home"
"$nix_env" --profile "$profiles/profile" -i "$home_path" >/dev/null

cat >"$snapshot/context.tsv" <<EOF
format	1
snapshot	$snapshot
stamp	20000101T000000Z
host	$(hostname -s)
user	$(id -un)
home	$home
repo	$repo_dir
repo_commit	$(git -C "$repo_dir" rev-parse HEAD)
candidate	$candidate
home_path	$home_path
home_files	$home_files
timer_unit	$unit
user_groups	$(id -G)
launcher_kind	symlink
launcher_link	/manual/codex
codex_config_kind	file
codex_config_mode	600
expected_codex_config_sha256	$(sha256sum "$snapshot/codex-config.expected" | awk '{print $1}')
EOF
cp -p -- "$operator" "$snapshot/dgx-home"
chmod 0700 -- "$snapshot/dgx-home"
printf 'Snapshot creation completed.\n' >"$snapshot/SNAPSHOT_COMPLETE"
(
  cd "$snapshot"
  find . -type f ! -name SHA256SUMS ! -name RETAINED ! -name ROLLED_BACK \
    -print0 | sort -z | xargs -0 sha256sum
) >"$snapshot/SHA256SUMS"

DGX_HOME_TEST_MODE=1 DGX_HOME_TEST_HOME="$home" \
  "$operator" rollback-snapshot "$snapshot" >/dev/null

[[ -L "$home/.local/bin/codex" &&
  "$(readlink -- "$home/.local/bin/codex")" == /manual/codex ]] ||
  fail 'manual Codex launcher was not restored'
cmp -s -- "$home/.codex/config.toml" "$snapshot/backup/codex_config" ||
  fail 'Codex config was not restored byte-for-byte'
for path in \
  "$home/.cache/.keep" \
  "$home/.local/state/.keep" \
  "$profiles/profile" \
  "$profiles/profile-1-link" \
  "$profiles/home-manager" \
  "$profiles/home-manager-1-link" \
  "$home/.local/state/home-manager/gcroots/current-home"; do
  [[ ! -e "$path" && ! -L "$path" ]] || fail "rollback left $path"
done
[[ -f "$snapshot/ROLLED_BACK" ]] || fail 'rollback evidence marker is absent'

printf 'PASS|dgx_home_rollback_test|exact first-generation profile, files, launcher, and config restored\n'
