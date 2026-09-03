#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [--check | --apply]\n' "$(basename "$0")" >&2
}

mode="check"
case "${1:-}" in
  "" | --check)
    ;;
  --apply)
    mode="apply"
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
source_file="$repo_dir/packages/zed-editor/source.json"
release_api="https://api.github.com/repos/zed-industries/zed/releases/latest"
tag_repository="https://github.com/zed-industries/zed.git"
architecture="aarch64"
asset="zed-linux-${architecture}.tar.gz"

for command_name in curl git jq nix; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'ERROR: required command is missing: %s\n' "$command_name" >&2
    exit 1
  fi
done

pinned_version="$(jq -er '.version' "$source_file")"
pinned_architecture="$(jq -er '.architecture' "$source_file")"
pinned_asset="$(jq -er '.asset' "$source_file")"
pinned_tag="$(jq -er '.releaseTag' "$source_file")"
pinned_commit="$(jq -er '.tagCommit' "$source_file")"
pinned_url="$(jq -er '.url' "$source_file")"
pinned_hash="$(jq -er '.hash' "$source_file")"
pinned_upstream_sha256="$(jq -er '.upstreamSha256' "$source_file")"

if [[ "$pinned_architecture" != "$architecture" || "$pinned_asset" != "$asset" ]]; then
  printf '%s\n' \
    "ERROR: this updater is intentionally limited to Zed stable for ARM64 Linux." >&2
  exit 1
fi

release_json="$(
  curl --fail --silent --show-error --location \
    --proto '=https' --tlsv1.2 --retry 2 --max-time 60 \
    -H 'Accept: application/vnd.github+json' "$release_api"
)"
candidate_tag="$(jq -er 'select(.draft == false and .prerelease == false) | .tag_name' <<<"$release_json")"
candidate_version="${candidate_tag#v}"
candidate_url="$(
  jq -er --arg asset "$asset" \
    '.assets[] | select(.name == $asset) | .browser_download_url' \
    <<<"$release_json"
)"
candidate_digest="$(
  jq -er --arg asset "$asset" \
    '.assets[] | select(.name == $asset) | .digest' <<<"$release_json"
)"
candidate_upstream_sha256="${candidate_digest#sha256:}"
candidate_commit="$(
  timeout 30s git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=15 \
    ls-remote --tags --refs "$tag_repository" "refs/tags/$candidate_tag" |
    awk 'NR == 1 { print $1 }'
)"

if [[ "$candidate_tag" != "v${candidate_version}" ||
      ! "$candidate_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ||
      ! "$candidate_upstream_sha256" =~ ^[0-9a-f]{64}$ ||
      ! "$candidate_commit" =~ ^[0-9a-f]{40}$ ]]; then
  printf '%s\n' "ERROR: invalid stable release metadata returned by Zed/GitHub." >&2
  exit 1
fi

expected_url="https://github.com/zed-industries/zed/releases/download/${candidate_tag}/${asset}"
if [[ "$candidate_url" != "$expected_url" ]]; then
  printf 'ERROR: unexpected stable asset URL: %s\n' "$candidate_url" >&2
  exit 1
fi

candidate_hash="$(
  nix hash convert --hash-algo sha256 --from base16 --to sri \
    "$candidate_upstream_sha256"
)"

if [[ "$pinned_version" == "$candidate_version" ]]; then
  if [[ "$pinned_tag" == "$candidate_tag" &&
        "$pinned_commit" == "$candidate_commit" &&
        "$pinned_url" == "$candidate_url" &&
        "$pinned_hash" == "$candidate_hash" &&
        "$pinned_upstream_sha256" == "$candidate_upstream_sha256" ]]; then
    printf 'Zed stable ARM64 pin is current: %s\n' "$pinned_version"
    exit 0
  fi

  printf '%s\n' \
    "ERROR: Zed's release metadata or tag changed without a version change." >&2
  printf '%s\n' "Refusing to rewrite the pin; investigate provenance manually." >&2
  exit 3
fi

oldest_version="$(
  printf '%s\n%s\n' "$pinned_version" "$candidate_version" |
    sort -V |
    head -n 1
)"
if [[ "$oldest_version" == "$candidate_version" ]]; then
  printf 'ERROR: latest release returned %s, older than pinned %s.\n' \
    "$candidate_version" "$pinned_version" >&2
  printf '%s\n' "Refusing to downgrade the Zed pin." >&2
  exit 3
fi

printf 'Zed stable ARM64 update: pinned=%s candidate=%s\n' \
  "$pinned_version" "$candidate_version"
printf 'Artifact: %s\n' "$candidate_url"
printf 'Published SHA-256: %s\n' "$candidate_upstream_sha256"

if [[ "$mode" == "check" ]]; then
  printf '%s\n' \
    "No file changed. Run with --apply, then review/build the package and graphical profile."
  exit 2
fi

temporary_file="$(mktemp "$repo_dir/packages/zed-editor/.source.json.XXXXXX")"
cleanup() {
  if [[ -n "${temporary_file:-}" && -e "$temporary_file" ]]; then
    rm -- "$temporary_file"
  fi
}
trap cleanup EXIT

jq -n \
  --arg architecture "$architecture" \
  --arg asset "$asset" \
  --arg hash "$candidate_hash" \
  --arg releaseTag "$candidate_tag" \
  --arg tagCommit "$candidate_commit" \
  --arg upstreamSha256 "$candidate_upstream_sha256" \
  --arg url "$candidate_url" \
  --arg version "$candidate_version" \
  '{
    architecture: $architecture,
    asset: $asset,
    hash: $hash,
    releaseTag: $releaseTag,
    tagCommit: $tagCommit,
    upstreamSha256: $upstreamSha256,
    url: $url,
    version: $version
  }' >"$temporary_file"
chmod 0644 "$temporary_file"
mv -- "$temporary_file" "$source_file"
temporary_file=""

printf 'Updated exact repository pin to Zed %s; nothing was built or activated.\n' \
  "$candidate_version"
