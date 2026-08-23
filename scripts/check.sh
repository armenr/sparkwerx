#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

exec nix \
  --extra-experimental-features "nix-command flakes" \
  flake check \
  --no-build \
  "$@"
