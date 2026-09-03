#!/usr/bin/env bash
set -euo pipefail

# Disposable user-space regression for the generation-update rollback path.
# It synthesizes an exact generation-one -> generation-two Home profile inside
# a private temporary home and proves rollback restores the complete prior
# profile/root/link/config inventory without touching the real Home profile.

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
operator=$repo_dir/scripts/dgx-home
nix_bin=/nix/var/nix/profiles/default/bin/nix
nix_env=/nix/var/nix/profiles/default/bin/nix-env
nix_args=(--extra-experimental-features "nix-command flakes")

fail() {
  printf 'FAIL|dgx_home_update_rollback_test|%s\n' "$1" >&2
  exit 1
}

capture_protected_units() {
  local unit load active fragment pid started
  for unit in \
    tailscaled.service \
    gdm.service \
    docker.service \
    dgx-dashboard.service \
    dgx-dashboard-admin.service \
    nvidia-persistenced.service; do
    load="$(systemctl show "$unit" -p LoadState --value)"
    active="$(systemctl show "$unit" -p ActiveState --value)"
    fragment="$(systemctl show "$unit" -p FragmentPath --value)"
    pid="$(systemctl show "$unit" -p MainPID --value)"
    started="$(systemctl show "$unit" -p ActiveEnterTimestampMonotonic --value)"
    [[ "$load" == loaded && "$active" == active ]] ||
      fail "$unit is not active for the disposable test"
    printf '%s\t%s\t%s\t%s\n' "$unit" "$fragment" "$pid" "$started"
  done
}

temp_dir="$(mktemp -d --tmpdir dgx-home-test.XXXXXXXX)"
cleanup() {
  rm -rf -- "$temp_dir"
}
trap cleanup EXIT

home=$temp_dir/home
snapshot=$temp_dir/snapshot
profiles=$home/.local/state/nix/profiles
gcroots=$home/.local/state/home-manager/gcroots
old_env_profile=$temp_dir/old-environment-profile
new_env_profile=$temp_dir/new-environment-profile

old_candidate="$($nix_bin "${nix_args[@]}" eval --raw \
  '.#homeConfigurations."n0b0dy@sparkle-01".activationPackage')"
new_candidate="$($nix_bin "${nix_args[@]}" eval --raw \
  '.#checks.aarch64-linux.home-update-rollback-fixture')"
$nix_bin "${nix_args[@]}" build --no-link \
  '.#checks.aarch64-linux.home-sparkle-01' \
  '.#checks.aarch64-linux.home-update-rollback-fixture'
[[ "$old_candidate" != "$new_candidate" ]] ||
  fail 'the disposable update fixture is not distinct'

old_home_path="$(readlink -e "$old_candidate/home-path")"
old_home_files="$(readlink -e "$old_candidate/home-files")"
new_home_path="$(readlink -e "$new_candidate/home-path")"
new_home_files="$(readlink -e "$new_candidate/home-files")"
$nix_env --profile "$old_env_profile" -i "$old_home_path" >/dev/null
$nix_env --profile "$new_env_profile" -i "$new_home_path" >/dev/null
old_environment="$(readlink -e "$old_env_profile")"
new_environment="$(readlink -e "$new_env_profile")"
[[ "$old_environment" != "$new_environment" ]] ||
  fail 'the disposable user environments are not distinct'

mkdir -p -- \
  "$home/.cache" \
  "$home/.codex" \
  "$home/.config" \
  "$home/.local/bin" \
  "$home/.local/state" \
  "$gcroots" \
  "$profiles" \
  "$snapshot/backup"
chmod 0700 -- "$snapshot"

# Snapshot inventory is generation one.
printf '%s\t%s\n' \
  home-manager home-manager-1-link \
  home-manager-1-link "$old_candidate" \
  profile profile-1-link \
  profile-1-link "$old_environment" \
  | sort >"$snapshot/profiles.before.tsv"
printf 'current-home\t%s\n' "$old_candidate" >"$snapshot/gcroots.before.tsv"

# The temporary live surface represents a completed generation-two update.
ln -s -- home-manager-2-link "$profiles/home-manager"
ln -s -- "$old_candidate" "$profiles/home-manager-1-link"
ln -s -- "$new_candidate" "$profiles/home-manager-2-link"
ln -s -- profile-2-link "$profiles/profile"
ln -s -- "$old_environment" "$profiles/profile-1-link"
ln -s -- "$new_environment" "$profiles/profile-2-link"
ln -s -- "$profiles/profile" "$home/.nix-profile"
ln -s -- "$new_candidate" "$gcroots/current-home"
ln -s -- "$new_home_files/.local/bin/codex" "$home/.local/bin/codex"
ln -s -- "$new_home_files/.cache/.keep" "$home/.cache/.keep"
ln -s -- "$new_home_files/.local/state/.keep" "$home/.local/state/.keep"

printf 'model = "preserve-me"\n' >"$snapshot/backup/codex_config"
cp -p -- "$snapshot/backup/codex_config" "$snapshot/codex-config.expected"
"$repo_dir/scripts/reconcile-codex-relaxed-defaults.sh" \
  --apply "$snapshot/codex-config.expected" >/dev/null
cp -p -- "$snapshot/codex-config.expected" "$home/.codex/config.toml"
capture_protected_units >"$snapshot/protected-units.before.tsv"

ln -s -- "$new_candidate" "$snapshot/candidate-root"
ln -s -- "$new_environment" "$snapshot/expected-profile"
unit=dgx-home-headless-update-rollback-test-never-armed
cat >"$snapshot/context.tsv" <<EOF
format	2
kind	headless-update
snapshot	$snapshot
stamp	20000101T000000Z
host	$(hostname -s)
user	$(id -un)
home	$home
repo	$repo_dir
repo_commit	$(git -C "$repo_dir" rev-parse HEAD)
old_candidate	$old_candidate
old_home_path	$old_home_path
old_home_files	$old_home_files
old_user_environment	$old_environment
old_home_manager_selected	home-manager-1-link
old_profile_selected	profile-1-link
candidate	$new_candidate
home_path	$new_home_path
home_files	$new_home_files
expected_user_environment	$new_environment
new_home_manager_generation	home-manager-2-link
new_profile_generation	profile-2-link
expected_codex_config_sha256	$(sha256sum "$snapshot/codex-config.expected" | awk '{print $1}')
timer_unit	$unit
user_groups	$(id -G)
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
  "$operator" rollback-update-snapshot "$snapshot" >/dev/null

[[ "$(readlink -- "$profiles/home-manager")" == home-manager-1-link &&
  "$(readlink -e "$profiles/home-manager")" == "$old_candidate" ]] ||
  fail 'Home Manager generation one was not reselected'
[[ "$(readlink -- "$profiles/profile")" == profile-1-link &&
  "$(readlink -e "$profiles/profile")" == "$old_environment" ]] ||
  fail 'user-profile generation one was not reselected'
[[ "$(readlink -- "$gcroots/current-home")" == "$old_candidate" ]] ||
  fail 'current-home did not return to the old candidate'
for path in "$profiles/home-manager-2-link" "$profiles/profile-2-link"; do
  [[ ! -e "$path" && ! -L "$path" ]] || fail "rollback retained $path"
done
[[ "$(readlink -- "$home/.local/bin/codex")" == "$old_home_files/.local/bin/codex" ]] ||
  fail 'Codex launcher was not restored to the old generation'
[[ "$(readlink -- "$home/.cache/.keep")" == "$old_home_files/.cache/.keep" ]] ||
  fail 'cache marker was not restored to the old generation'
[[ "$(readlink -- "$home/.local/state/.keep")" == "$old_home_files/.local/state/.keep" ]] ||
  fail 'state marker was not restored to the old generation'
cmp -s -- "$home/.codex/config.toml" "$snapshot/backup/codex_config" ||
  fail 'Codex config was not restored byte-for-byte'
[[ -f "$snapshot/ROLLED_BACK" ]] || fail 'rollback evidence marker is absent'

# Exercise an interrupted activation after Home's write boundary: the new Home
# generation and temporary GC root exist, the user profile is still old, and
# one managed link has temporarily disappeared.
unlink -- "$profiles/home-manager"
ln -s -- home-manager-2-link "$profiles/home-manager"
ln -s -- "$new_candidate" "$profiles/home-manager-2-link"
ln -s -- "$new_candidate" "$gcroots/new-home"
unlink -- "$home/.cache/.keep"
cp -p -- "$snapshot/codex-config.expected" "$home/.codex/config.toml"

DGX_HOME_TEST_MODE=1 DGX_HOME_TEST_HOME="$home" \
  "$operator" rollback-update-snapshot "$snapshot" >/dev/null

[[ "$(readlink -- "$profiles/home-manager")" == home-manager-1-link &&
  "$(readlink -e "$profiles/home-manager")" == "$old_candidate" ]] ||
  fail 'partial rollback did not reselect Home Manager generation one'
[[ "$(readlink -- "$profiles/profile")" == profile-1-link &&
  "$(readlink -e "$profiles/profile")" == "$old_environment" ]] ||
  fail 'partial rollback changed the old user profile'
for path in "$profiles/home-manager-2-link" "$profiles/profile-2-link" "$gcroots/new-home"; do
  [[ ! -e "$path" && ! -L "$path" ]] || fail "partial rollback retained $path"
done
[[ "$(readlink -- "$home/.cache/.keep")" == "$old_home_files/.cache/.keep" ]] ||
  fail 'partial rollback did not recreate the old cache marker'
cmp -s -- "$home/.codex/config.toml" "$snapshot/backup/codex_config" ||
  fail 'partial rollback did not restore the Codex config'

printf 'PASS|dgx_home_update_rollback_test|completed and partial updates restored exact previous profile, roots, managed links, and config\n'
