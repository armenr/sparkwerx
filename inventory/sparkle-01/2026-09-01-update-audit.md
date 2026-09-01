# Online update audit — 2026-09-01

## Scope and result

- Timestamp: 2026-09-01T11:59:27Z
- Host: sparkle-01 (`aarch64-linux`)
- Mode: online, read-only
- Result: no pins, packages, profiles, services, images, or host settings changed
- Retained root-canary classifier: `ACTIVE_RETAINED`

The audit queried public authoritative release/ref sources and inspected only
sanitized local state. It did not refresh `flake.lock`, update package indexes,
inspect browser profiles, read raw Tailscale identity/status data, pull images,
run a root-assisted container build, or activate/register anything.

## Actionable comparison

| Component | Current or locked | Official candidate | Status | Decision |
| --- | --- | --- | --- | --- |
| Nix runtime | 2.35.2 | 2.35.2 | CURRENT | Keep the verified runtime |
| Default `upgrade-nix` fallback | active 2.35.2 | 2.34.8 | HOLD | Continue blocking this downgrade |
| Tailscale apt/package pin | 1.102.3 | 1.102.3 | CURRENT | Keep apt ownership until the separate migration |
| Stock stable-Nixpkgs Tailscale | installed 1.102.3 | 1.98.10 | HOLD | Do not substitute; it would downgrade access |
| Nixpkgs stable ref | `a9e6d84f9c2f...` | `c5c4a43b0e8056328ec4529f735cabdb8f1942bb` | UPDATE_AVAILABLE | Separate lock-refresh review |
| Nixpkgs apps ref | `a831408e6378...` | `e8be7818e19ada32105a8af937a6a473b38167ca` | UPDATE_AVAILABLE | Separate lock-refresh review |
| Home Manager | `65258d5c65a2...` | same matching branch head | CURRENT | No change |
| System Manager | `05e08c6dd739...` | same matching branch head | CURRENT | Keep exact retained candidate |
| Hyprland | 0.56.2 | 0.56.2 | CURRENT | Still inactive |
| ncdu | 2.9.2 | 2.9.2 | CURRENT | Selected, not installed |
| lazydocker | 0.25.2 | 0.25.2 | CURRENT | Selected, not installed |
| Devbox | 0.18.0 | 0.18.0 | CURRENT | Built adapter remains current |
| Ghostty | 1.3.1 | 1.3.1 | CURRENT | Selected graphical role remains inactive |
| Chromium | 151.0.7922.173 | 152.0.7977.64 | UPDATE_AVAILABLE | Refresh apps only after approval and re-review |
| Zed | 1.16.1 | 1.17.2 | UPDATE_AVAILABLE | Refresh apps only after approval and re-review |
| LM Studio desktop | 0.4.21-2 | 0.4.23-1 | UPDATE_AVAILABLE | Refresh apps only after approval and re-review |
| DGX Spark playbooks | absent | `1fb66f059ee4...` branch head | NOT_PINNED | Pin only with the first selected workload |
| Codex CLI manual install | 0.152.0 | 0.152.0 | CURRENT | Ownership migration remains separate |
| ChatGPT, Firefox, 1Password extension | manual/factory | manual channel check | MANUAL | No profile inspection or replacement |

NVIDIA-owned DGX OS, kernel, driver, CUDA compatibility, Docker, Compose, and
Container Toolkit remain Dashboard/vendor-managed. Their locally observed
versions were inventoried but generic upstream versions were not treated as
applicable updates.

## Sources

- [Nix releases](https://github.com/NixOS/nix/releases)
- [Tailscale stable packages](https://pkgs.tailscale.com/stable/)
- [Stable Nixpkgs branch](https://github.com/NixOS/nixpkgs/tree/nixos-26.05)
- [Apps Nixpkgs branch](https://github.com/NixOS/nixpkgs/tree/nixpkgs-unstable)
- [Home Manager matching branch](https://github.com/nix-community/home-manager/tree/release-26.05)
- [System Manager matching branch](https://github.com/numtide/system-manager/tree/release-26.05)
- [Hyprland releases](https://github.com/hyprwm/Hyprland/releases)
- [ncdu releases](https://dev.yorhel.nl/ncdu)
- [lazydocker releases](https://github.com/jesseduffield/lazydocker/releases)
- [Devbox releases](https://github.com/jetify-com/devbox/releases)
- [Ghostty release notes](https://ghostty.org/docs/install/release-notes)
- [Chromium Linux releases](https://chromiumdash.appspot.com/releases?platform=Linux)
- [Zed releases](https://github.com/zed-industries/zed/releases)
- [LM Studio download](https://lmstudio.ai/download)
- [DGX Spark playbooks](https://github.com/NVIDIA/dgx-spark-playbooks)

## Next gates

1. Do not refresh either Nixpkgs input as part of the System Manager
   registration work.
2. Separately authorize and pass the exact disposable registration lifecycle
   test before designing any live generation registration.
3. If an apps refresh is approved, update only the apps input first, inspect the
   three direct candidates and transitive diff, then build without activation.
4. Keep the NVIDIA playbooks unpinned until a specific workload is selected for
   implementation.
