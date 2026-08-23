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
source_file="$repo_dir/packages/tailscale/source.json"

for command_name in curl jq nix tailscale timeout; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'ERROR: required command is missing: %s\n' "$command_name" >&2
    exit 1
  fi
done

pinned_version="$(jq -er '.version' "$source_file")"
pinned_architecture="$(jq -er '.architecture' "$source_file")"
pinned_track="$(jq -er '.track' "$source_file")"
pinned_url="$(jq -er '.url' "$source_file")"
pinned_hash="$(jq -er '.hash' "$source_file")"
pinned_upstream_sha256="$(jq -er '.upstreamSha256' "$source_file")"

if [[ "$pinned_architecture" != "arm64" || "$pinned_track" != "stable" ]]; then
  printf '%s\n' \
    "ERROR: this updater is intentionally limited to the stable ARM64 fleet pin." >&2
  exit 1
fi

upstream_json="$(
  timeout 30s tailscale version --json --upstream --track stable
)"
candidate_version="$(
  jq -er '.upstream // empty' <<<"$upstream_json"
)"

if [[ ! "$candidate_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'ERROR: invalid stable version returned by Tailscale: %s\n' \
    "$candidate_version" >&2
  exit 1
fi

candidate_url="https://pkgs.tailscale.com/stable/tailscale_${candidate_version}_arm64.tgz"
checksum_url="${candidate_url}.sha256"
checksum_document="$(
  curl --fail --silent --show-error --location \
    --proto '=https' --tlsv1.2 --retry 2 --max-time 60 \
    "$checksum_url"
)"
candidate_upstream_sha256="$(
  awk 'NR == 1 { print tolower($1) }' <<<"$checksum_document"
)"

if [[ ! "$candidate_upstream_sha256" =~ ^[0-9a-f]{64}$ ]]; then
  printf 'ERROR: invalid checksum returned by %s\n' "$checksum_url" >&2
  exit 1
fi

candidate_hash="$(
  nix hash convert --hash-algo sha256 --from base16 --to sri \
    "$candidate_upstream_sha256"
)"

if [[ "$pinned_version" == "$candidate_version" ]]; then
  if [[ "$pinned_url" == "$candidate_url" &&
        "$pinned_hash" == "$candidate_hash" &&
        "$pinned_upstream_sha256" == "$candidate_upstream_sha256" ]]; then
    printf 'Tailscale stable ARM64 pin is current: %s\n' "$pinned_version"
    exit 0
  fi

  printf '%s\n' \
    "ERROR: Tailscale's published artifact metadata changed without a version change." >&2
  printf '%s\n' \
    "Refusing to rewrite the pin; investigate upstream provenance manually." >&2
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
  printf '%s\n' "Refusing to downgrade the fleet access-plane pin." >&2
  exit 3
fi

printf 'Tailscale stable ARM64 update: pinned=%s candidate=%s\n' \
  "$pinned_version" "$candidate_version"
printf 'Artifact: %s\n' "$candidate_url"
printf 'Published SHA-256: %s\n' "$candidate_upstream_sha256"

if [[ "$mode" == "check" ]]; then
  printf '%s\n' \
    "No file changed. Run with --apply, then review/build the package and unit."
  exit 2
fi

temporary_file="$(mktemp "$repo_dir/packages/tailscale/.source.json.XXXXXX")"
cleanup() {
  if [[ -n "${temporary_file:-}" && -e "$temporary_file" ]]; then
    rm -- "$temporary_file"
  fi
}
trap cleanup EXIT

jq -n \
  --arg architecture "arm64" \
  --arg hash "$candidate_hash" \
  --arg track "stable" \
  --arg upstreamSha256 "$candidate_upstream_sha256" \
  --arg url "$candidate_url" \
  --arg version "$candidate_version" \
  '{
    architecture: $architecture,
    hash: $hash,
    track: $track,
    upstreamSha256: $upstreamSha256,
    url: $url,
    version: $version
  }' >"$temporary_file"
chmod 0644 "$temporary_file"
mv -- "$temporary_file" "$source_file"
temporary_file=""

printf 'Updated exact repository pin to Tailscale %s; nothing was built or activated.\n' \
  "$candidate_version"
