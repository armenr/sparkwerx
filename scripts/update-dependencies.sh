#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

nix_command=(
  nix
  --extra-experimental-features
  "nix-command flakes"
)

root_fingerprint() {
  "${nix_command[@]}" eval --json --no-write-lock-file \
    .#lib.dgxRootManagerManifest.aarch64-linux |
    jq -Sc '{
      foundationNixpkgs,
      manager: {
        rev: .manager.rev,
        drvPath: .manager.drvPath,
        rootOutputPath: .manager.rootOutputPath
      },
      exactCandidates: .bootPersistence.exactCandidates,
      recoveryBundle: .bootPersistence.rebootRecovery.productionBundle,
      tests: {
        activation: .isolatedTest.currentDrvPath,
        registration: .registration.isolatedLifecycleTest.currentDrvPath,
        firstRegistration: .registration.guardedFirstGeneration.isolatedTransactionTest.currentDrvPath,
        generationSwitch: .registration.guardedGenerationSwitch.isolatedTransactionTest.currentDrvPath,
        bootPersistence: .bootPersistence.isolatedTransactionTest.currentDrvPath,
        rebootRecovery: .bootPersistence.rebootRecovery.isolatedTransactionTest.currentDrvPath
      }
    }'
}

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

# System Manager and nixpkgs-root are a frozen, separately reviewed lane. A
# user/package refresh must leave their complete evidence fingerprint exact.
root_before="$(root_fingerprint)"
"${nix_command[@]}" flake update nixpkgs nixpkgs-apps home-manager
root_after="$(root_fingerprint)"
if [[ "$root_after" != "$root_before" ]]; then
  printf '%s\n' \
    "The user/package update changed the frozen root lane; refusing to continue." >&2
  exit 1
fi
printf '%s\n' "Root lane remained byte-for-byte identity-stable."

./scripts/update-tailscale.sh --apply
./scripts/update-codex.sh --apply
./scripts/update-lmstudio.sh --apply
./scripts/update-zed.sh --apply

"${nix_command[@]}" fmt
./scripts/check.sh
"${nix_command[@]}" build \
  .#checks.aarch64-linux.home-sparkle-01 \
  .#checks.aarch64-linux.home-base \
  .#checks.aarch64-linux.home-graphical \
  .#checks.aarch64-linux.home-hyprland \
  .#checks.aarch64-linux.home-hyprland-with-portal \
  .#checks.aarch64-linux.home-update-rollback-fixture \
  .#checks.aarch64-linux.chromium-package \
  .#checks.aarch64-linux.chromium-policy \
  .#checks.aarch64-linux.codex-cli-package \
  .#checks.aarch64-linux.codex-cli-policy \
  .#checks.aarch64-linux.lmstudio-package \
  .#checks.aarch64-linux.lmstudio-policy \
  .#checks.aarch64-linux.zed-editor-package \
  .#checks.aarch64-linux.zed-editor-policy \
  .#checks.aarch64-linux.profile-policy \
  .#checks.aarch64-linux.root-manager-policy \
  .#checks.aarch64-linux.root-system-canary \
  .#checks.aarch64-linux.devbox-package \
  .#checks.aarch64-linux.devbox-policy \
  .#checks.aarch64-linux.tailscale-package \
  .#checks.aarch64-linux.tailscale-policy \
  .#checks.aarch64-linux.tailscaled-unit \
  .#chromium \
  .#devbox \
  .#codex-cli \
  .#hyprland \
  .#lmstudio \
  .#tailscale \
  .#tailscaled-unit \
  .#xdg-desktop-portal-hyprland \
  .#zed-editor \
  --no-link

./scripts/test-dgx-home-rollback.sh
./scripts/test-dgx-home-update-rollback.sh

printf '%s\n' \
  "Root-canary activation/rollback test remains a separate reviewed gate:" \
  "  sudo ./scripts/test-root-canary.sh"
