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

for command_name in curl python3 sha256sum stat timeout; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'ERROR: required command is missing: %s\n' "$command_name" >&2
    exit 1
  fi
done

json_value() {
  python3 - "$source_file" "$1" <<'PY'
import json
import sys

path, expression = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    value = json.load(handle)
for component in expression.split("."):
    value = value[component]
print(value)
PY
}

pinned_project="$(json_value installer.project)"
pinned_version="$(json_value installer.version)"
pinned_tag="$(json_value installer.releaseTag)"
pinned_asset="$(json_value installer.asset)"
pinned_url="$(json_value installer.url)"
pinned_size="$(json_value installer.size)"
pinned_sha256="$(json_value installer.sha256)"
pinned_embedded_nix="$(json_value installer.embeddedNixVersion)"

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
mapfile -t release_fields < <(
  python3 - "$asset" 3<<<"$release_json" <<'PY'
import json
import os
import sys

asset_name = sys.argv[1]
release = json.load(os.fdopen(3))
assets = [item for item in release.get("assets", []) if item.get("name") == asset_name]
if len(assets) != 1:
    raise SystemExit("expected exactly one ARM64 Linux asset")
item = assets[0]
for value in (
    release.get("tag_name", ""),
    item.get("browser_download_url", ""),
    item.get("size", ""),
    item.get("digest", ""),
):
    print(value)
PY
)
[[ "${#release_fields[@]}" -eq 4 ]] ||
  { printf '%s\n' 'ERROR: incomplete release metadata returned by GitHub.' >&2; exit 1; }
candidate_tag=${release_fields[0]}
candidate_version=${candidate_tag#v}
candidate_url=${release_fields[1]}
candidate_size=${release_fields[2]}
candidate_digest=${release_fields[3]}
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

python3 - "$source_file" "$temporary_json" "$project" "$candidate_version" \
  "$candidate_tag" "$asset" "$candidate_url" "$candidate_size" \
  "$candidate_sha256" <<'PY'
import json
import sys

(
    source_path,
    output_path,
    project,
    version,
    release_tag,
    asset,
    url,
    size,
    sha256,
) = sys.argv[1:]
with open(source_path, encoding="utf-8") as handle:
    source = json.load(handle)
source["installer"] = {
    "project": project,
    "version": version,
    "releaseTag": release_tag,
    "asset": asset,
    "url": url,
    "size": int(size),
    "sha256": sha256,
    "embeddedNixVersion": version,
}
with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(source, handle, indent=2)
    handle.write("\n")
PY
chmod 0644 "$temporary_json"
mv -- "$temporary_json" "$source_file"
temporary_json=""

printf 'Updated exact repository pin to nix-installer %s; nothing was installed.\n' \
  "$candidate_version"
