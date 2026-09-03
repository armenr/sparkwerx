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
source_file="$repo_dir/packages/lmstudio/source.json"
latest_url="https://lmstudio.ai/download/latest/linux/arm64"

for command_name in curl jq nix; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'ERROR: required command is missing: %s\n' "$command_name" >&2
    exit 1
  fi
done

pinned_version="$(jq -er '.version' "$source_file")"
pinned_architecture="$(jq -er '.architecture' "$source_file")"
pinned_format="$(jq -er '.format' "$source_file")"
pinned_url="$(jq -er '.url' "$source_file")"
pinned_hash="$(jq -er '.hash' "$source_file")"

if [[ "$pinned_architecture" != "arm64" || "$pinned_format" != "AppImage" ||
      ! "$pinned_hash" =~ ^sha256-[A-Za-z0-9+/]{43}=$ ]]; then
  printf '%s\n' \
    "ERROR: the repository pin is not a valid Linux ARM64 AppImage record." >&2
  exit 1
fi

candidate_url="$(
  curl --fail --silent --show-error --location --head \
    --proto '=https' --tlsv1.2 --retry 2 --max-time 60 \
    --write-out '%{url_effective}' --output /dev/null "$latest_url"
)"
candidate_version="$(
  sed -nE \
    's#^https://installers\.lmstudio\.ai/linux/arm64/([0-9]+\.[0-9]+\.[0-9]+-[0-9]+)/LM-Studio-\1-arm64\.AppImage$#\1#p' \
    <<<"$candidate_url"
)"

if [[ -z "$candidate_version" ]]; then
  printf 'ERROR: unexpected official ARM64 redirect: %s\n' "$candidate_url" >&2
  exit 1
fi

if [[ "$pinned_version" == "$candidate_version" ]]; then
  if [[ "$pinned_url" != "$candidate_url" ]]; then
    printf '%s\n' \
      "ERROR: the official artifact URL changed without a version change." >&2
    printf '%s\n' "Refusing to rewrite the pin; investigate provenance manually." >&2
    exit 3
  fi

  printf 'LM Studio Linux ARM64 pin is current: %s\n' "$pinned_version"
  exit 0
fi

oldest_version="$(
  printf '%s\n%s\n' "$pinned_version" "$candidate_version" |
    sort -V |
    head -n 1
)"
if [[ "$oldest_version" == "$candidate_version" ]]; then
  printf 'ERROR: official redirect returned %s, older than pinned %s.\n' \
    "$candidate_version" "$pinned_version" >&2
  printf '%s\n' "Refusing to downgrade the LM Studio pin." >&2
  exit 3
fi

printf 'LM Studio Linux ARM64 update: pinned=%s candidate=%s\n' \
  "$pinned_version" "$candidate_version"
printf 'Artifact: %s\n' "$candidate_url"

if [[ "$mode" == "check" ]]; then
  printf '%s\n' \
    "No file changed. Run with --apply to fetch/hash the AppImage, then review/build the package."
  exit 2
fi

prefetch_json="$(
  nix --extra-experimental-features "nix-command flakes" \
    store prefetch-file --json --hash-type sha256 "$candidate_url"
)"
candidate_hash="$(jq -er '.hash' <<<"$prefetch_json")"

temporary_file="$(mktemp "$repo_dir/packages/lmstudio/.source.json.XXXXXX")"
cleanup() {
  if [[ -n "${temporary_file:-}" && -e "$temporary_file" ]]; then
    rm -- "$temporary_file"
  fi
}
trap cleanup EXIT

jq \
  --arg hash "$candidate_hash" \
  --arg url "$candidate_url" \
  --arg version "$candidate_version" \
  '.hash = $hash | .url = $url | .version = $version' \
  "$source_file" >"$temporary_file"
chmod 0644 "$temporary_file"
mv -- "$temporary_file" "$source_file"
temporary_file=""

printf 'Updated exact repository pin to LM Studio %s; nothing was built or activated.\n' \
  "$candidate_version"
