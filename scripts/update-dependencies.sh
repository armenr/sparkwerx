#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

nix_command=(
  nix
  --extra-experimental-features
  "nix-command flakes"
)

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' "jq is required to audit the pinned Devbox release." >&2
  exit 1
fi

pinned_devbox="$(jq -er '.version' packages/devbox/source.json)"
latest_devbox="$({
  git ls-remote --tags --refs https://github.com/jetify-com/devbox.git \
    'refs/tags/*'
} | awk '{ sub("refs/tags/", "", $2); print $2 }' \
  | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
  | sort -V \
  | tail -n 1)"

if [[ -z "$pinned_devbox" || -z "$latest_devbox" ]]; then
  printf '%s\n' "Unable to determine pinned/latest Devbox versions." >&2
  exit 1
fi

if [[ "$pinned_devbox" != "$latest_devbox" ]]; then
  printf 'Devbox update available: pinned=%s latest=%s\n' \
    "$pinned_devbox" "$latest_devbox" >&2
  printf '%s\n' \
    "Update the source and Go vendor hashes, then build the ARM64 package." >&2
  exit 2
fi

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

"${nix_command[@]}" flake update nixpkgs nixpkgs-apps home-manager system-manager
./scripts/update-tailscale.sh --apply

"${nix_command[@]}" fmt
./scripts/check.sh
"${nix_command[@]}" build \
  .#checks.aarch64-linux.home-sparkle-01 \
  .#checks.aarch64-linux.home-base \
  .#checks.aarch64-linux.home-graphical \
  .#checks.aarch64-linux.home-hyprland \
  .#checks.aarch64-linux.home-hyprland-with-portal \
  .#checks.aarch64-linux.profile-policy \
  .#checks.aarch64-linux.root-manager-policy \
  .#checks.aarch64-linux.root-system-canary \
  .#checks.aarch64-linux.devbox-package \
  .#checks.aarch64-linux.devbox-policy \
  .#checks.aarch64-linux.tailscale-package \
  .#checks.aarch64-linux.tailscale-policy \
  .#checks.aarch64-linux.tailscaled-unit \
  .#devbox \
  .#hyprland \
  .#tailscale \
  .#tailscaled-unit \
  .#xdg-desktop-portal-hyprland \
  --no-link

printf '%s\n' \
  "Root-canary activation/rollback test remains a separate reviewed gate:" \
  "  sudo ./scripts/test-root-canary.sh"
