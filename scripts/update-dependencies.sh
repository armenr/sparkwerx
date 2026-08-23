#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

nix_command=(
  nix
  --extra-experimental-features
  "nix-command flakes"
)

"${nix_command[@]}" flake update nixpkgs nixpkgs-apps home-manager

pinned_hyprland="$({
  sed -n 's|.*Hyprland/v\([0-9][0-9.]*\)";|\1|p' flake.nix
} | head -n 1)"

latest_hyprland="$({
  git ls-remote --tags --refs https://github.com/hyprwm/Hyprland.git \
    'refs/tags/v*'
} | awk '{ sub("refs/tags/v", "", $2); print $2 }' \
  | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
  | sort -V \
  | tail -n 1)"

if [[ -z "$pinned_hyprland" || -z "$latest_hyprland" ]]; then
  printf '%s\n' "Unable to determine pinned/latest Hyprland versions." >&2
  exit 1
fi

if [[ "$pinned_hyprland" != "$latest_hyprland" ]]; then
  printf 'Hyprland update available: pinned=%s latest=%s\n' \
    "$pinned_hyprland" "$latest_hyprland" >&2
  printf '%s\n' "Review and bump the flake input before rollout." >&2
  exit 2
fi

"${nix_command[@]}" fmt
./scripts/check.sh
"${nix_command[@]}" build \
  .#checks.aarch64-linux.home-sparkle-01 \
  .#checks.aarch64-linux.home-base \
  .#checks.aarch64-linux.home-graphical \
  .#checks.aarch64-linux.home-hyprland \
  .#checks.aarch64-linux.home-hyprland-with-portal \
  .#checks.aarch64-linux.profile-policy \
  .#hyprland \
  .#xdg-desktop-portal-hyprland \
  --no-link
