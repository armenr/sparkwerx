#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [--check | --apply]\n' "$(basename "$0")" >&2
}

mode=check
case "${1:-}" in
  "" | --check)
    ;;
  --apply)
    mode=apply
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 64
    ;;
esac

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source_file=$repo_dir/bootstrap/nix/source.json
project=NixOS/nix-installer
asset=nix-installer-aarch64-linux

for command_name in curl jq sha256sum stat timeout; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'ERROR: required command is missing: %s\n' "$command_name" >&2
    exit 1
  fi
done

pinned_project="$(jq -er '.installer.project' "$source_file")"
pinned_version="$(jq -er '.installer.version' "$source_file")"
pinned_tag="$(jq -er '.installer.releaseTag' "$source_file")"
pinned_asset="$(jq -er '.installer.asset' "$source_file")"
pinned_url="$(jq -er '.installer.url' "$source_file")"
pinned_size="$(jq -er '.installer.size' "$source_file")"
pinned_sha256="$(jq -er '.installer.sha256' "$source_file")"
pinned_embedded_nix="$(jq -er '.installer.embeddedNixVersion' "$source_file")"

if [[ "$pinned_project" != "$project" || "$pinned_asset" != "$asset" ]]; then
  printf '%s\n' \
    'ERROR: this updater is intentionally limited to the official ARM64 Linux nix-installer.' >&2
  exit 1
fi

release_json="$(
  timeout 30s curl --fail --silent --show-error --location \
    --proto '=https' --tlsv1.2 --retry 2 --max-time 60 \
    "https://api.github.com/repos/$project/releases/latest"
)"
candidate_tag="$(jq -er '.tag_name' <<<"$release_json")"
candidate_version=${candidate_tag#v}
candidate_url="$(
  jq -er --arg asset "$asset" \
    '.assets[] | select(.name == $asset) | .browser_download_url' \
    <<<"$release_json"
)"
candidate_size="$(
  jq -er --arg asset "$asset" \
    '.assets[] | select(.name == $asset) | .size' <<<"$release_json"
)"
candidate_digest="$(
  jq -er --arg asset "$asset" \
    '.assets[] | select(.name == $asset) | .digest' <<<"$release_json"
)"
candidate_published_sha256=${candidate_digest#sha256:}
expected_url="https://github.com/$project/releases/download/$candidate_tag/$asset"

if [[ ! "$candidate_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ||
      "$candidate_tag" != "$candidate_version" ||
      "$candidate_url" != "$expected_url" ||
      ! "$candidate_size" =~ ^[1-9][0-9]*$ ||
      ! "$candidate_published_sha256" =~ ^[0-9a-f]{64}$ ]]; then
  printf '%s\n' 'ERROR: invalid stable release metadata returned by GitHub.' >&2
  exit 1
fi

temporary_file="$(mktemp)"
cleanup() {
  rm -f -- "$temporary_file"
}
trap cleanup EXIT

curl --fail --silent --show-error --location \
  --proto '=https' --tlsv1.2 --retry 2 --max-time 120 \
  --output "$temporary_file" "$candidate_url"
candidate_sha256="$(sha256sum "$temporary_file" | awk '{print $1}')"
downloaded_size="$(stat -c %s "$temporary_file")"

if [[ "$candidate_sha256" != "$candidate_published_sha256" ||
      "$downloaded_size" != "$candidate_size" ]]; then
  printf '%s\n' \
    'ERROR: downloaded nix-installer does not match GitHub release metadata.' >&2
  exit 3
fi

chmod 0700 "$temporary_file"
candidate_binary_version="$("$temporary_file" --version | awk '{print $NF}')"
if [[ "$candidate_binary_version" != "$candidate_version" ]]; then
  printf 'ERROR: downloaded installer reports %s, expected %s.\n' \
    "$candidate_binary_version" "$candidate_version" >&2
  exit 3
fi

if [[ "$pinned_version" == "$candidate_version" ]]; then
  if [[ "$pinned_tag" == "$candidate_tag" &&
        "$pinned_url" == "$candidate_url" &&
        "$pinned_size" == "$candidate_size" &&
        "$pinned_sha256" == "$candidate_sha256" &&
        "$pinned_embedded_nix" == "$candidate_version" ]]; then
    printf 'Nix installer stable ARM64 pin is current: %s\n' "$pinned_version"
    exit 0
  fi

  printf '%s\n' \
    "ERROR: nix-installer's published artifact metadata changed without a version change." >&2
  printf '%s\n' \
    'Refusing to rewrite the pin; investigate upstream provenance manually.' >&2
  exit 3
fi

oldest_version="$(
  printf '%s\n%s\n' "$pinned_version" "$candidate_version" |
    sort -V |
    head -n 1
)"
if [[ "$oldest_version" == "$candidate_version" ]]; then
  printf 'ERROR: stable query returned %s, older than pinned %s.\n' \
    "$candidate_version" "$pinned_version" >&2
  printf '%s\n' 'Refusing to downgrade the Nix bootstrap pin.' >&2
  exit 3
fi

printf 'Nix installer stable ARM64 update: pinned=%s candidate=%s\n' \
  "$pinned_version" "$candidate_version"
printf 'Artifact: %s\n' "$candidate_url"
printf 'Published SHA-256: %s\n' "$candidate_sha256"

if [[ "$mode" == check ]]; then
  printf '%s\n' \
    'No file changed. Run with --apply, then review the fresh-host bootstrap plan.'
  exit 2
fi

temporary_json="$(mktemp "$repo_dir/bootstrap/nix/.source.json.XXXXXX")"
cleanup_json() {
  rm -f -- "$temporary_file" "$temporary_json"
}
trap cleanup_json EXIT

jq \
  --arg project "$project" \
  --arg version "$candidate_version" \
  --arg releaseTag "$candidate_tag" \
  --arg asset "$asset" \
  --arg url "$candidate_url" \
  --argjson size "$candidate_size" \
  --arg sha256 "$candidate_sha256" \
  --arg embeddedNixVersion "$candidate_version" \
  '.installer = {
    project: $project,
    version: $version,
    releaseTag: $releaseTag,
    asset: $asset,
    url: $url,
    size: $size,
    sha256: $sha256,
    embeddedNixVersion: $embeddedNixVersion
  }' "$source_file" >"$temporary_json"
chmod 0644 "$temporary_json"
mv -- "$temporary_json" "$source_file"
temporary_json=""

printf 'Updated exact repository pin to nix-installer %s; nothing was installed.\n' \
  "$candidate_version"
