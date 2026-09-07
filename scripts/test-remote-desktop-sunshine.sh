#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
if [[ "$EUID" -eq 0 ]]; then
  printf '%s\n' 'Run as your normal user; sudo is requested only for the temporary GPU test.' >&2
  exit 1
fi
if [[ "${1:-}" == inspect ]]; then
  exec ./scripts/test-remote-desktop-session.sh "$@"
fi
preset="${1:-4k120}"
if [[ "$#" -gt 1 || ! "$preset" =~ ^(1440p120|4k60|4k120)$ ]]; then
  printf '%s\n' 'Usage: ./scripts/test-remote-desktop-sunshine.sh [1440p120|4k60|4k120] | inspect SNAPSHOT_NAME' >&2
  exit 1
fi
# The stock locked build explicitly disables CUDA. For this release that
# removes Wayland's CUDA/GL encoder device even though NVENC codec names still
# appear in the binary. Reject it before building the GPU bundle or using sudo.
# The replacement must explicitly enable CUDA and fail if its compiler is
# missing. These flags are a prerequisite, not hardware/streaming evidence.
cuda_required="$(nix --extra-experimental-features 'nix-command flakes' \
  eval --json --no-write-lock-file .#sunshine --apply '
    p: let flags = p.cmakeFlags or []; in
      builtins.elem "-DSUNSHINE_ENABLE_CUDA:BOOL=TRUE" flags
      && builtins.elem "-DCUDA_FAIL_ON_MISSING:BOOL=TRUE" flags
      && !(builtins.elem "-DSUNSHINE_ENABLE_CUDA:BOOL=FALSE" flags)
  ')"
if [[ "$cuda_required" != true ]]; then
  printf '%s\n' \
    'FAIL|sunshine_build|the selected Sunshine build does not explicitly require CUDA support' \
    'The stock candidate cannot test Wayland/NVENC. See docs/remote-desktop.md before retrying.' \
    'NO_GPU_TEST: no sudo, service, driver, network, or desktop operation was performed.' >&2
  exit 1
fi
nix --extra-experimental-features 'nix-command flakes' build --no-link --no-write-lock-file \
  .#sunshine-policy .#remote-desktop-sunshine-startup-test .#remote-desktop-sunshine-startup-policy
test_bundle="$(nix --extra-experimental-features 'nix-command flakes' \
  eval --raw --no-write-lock-file .#remote-desktop-sunshine-startup-test.outPath)"
printf '%s\n' 'INFO|sunshine_test|temporary Hyprland plus Sunshine startup; no input or TCP/UDP; not a stream/FPS test'
exec sudo -- "$test_bundle/bin/dgx-remote-desktop-sunshine-startup-test" --repo "$repo_dir" --preset "$preset"
