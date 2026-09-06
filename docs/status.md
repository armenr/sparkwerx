# Status and support

[Documentation](README.md) · [Roadmap](roadmap.md)

For your machine's status, use the [status commands](operations.md#status-checks).

## Pilot: sparkle-01

| Layer | State |
| --- | --- |
| Factory OS | NVIDIA DGX OS 7.5.0; Ubuntu-based ARM64 with GB10 |
| Nix runtime | 2.35.2 in the machine-wide default profile |
| Provisioning artifact | Official Nix installer 2.35.1; intentionally distinct from runtime |
| Home | Generation one; `ncdu`, `lazydocker`, Devbox, Armen's Codex CLI, and Home Manager's session-variable file |
| Root configuration | System Manager generation five, selected/live/boot-linked |
| Desktop | Confirmed headless; factory GDM and Dashboard GUI stopped, not uninstalled |
| Access | Nix-owned Tailscale 1.102.3 with existing identity and Tailscale SSH preserved |
| Recovery | No transition timer armed in the latest retained-state record; all five pilot generations and their roots retained |

The recorded root classification is
`ACTIVE_REGISTERED_GENERATION_FIVE_HEADLESS_TAILSCALE_NIX_MANAGED`.
The [headless integration record](../root/desktop/validation/2026-09-05-confirmed-headless-integration.md)
is the current pilot reference. Don't apply that five-generation expectation to
a freshly provisioned node: the generic workflow uses two root generations.

## What the tests establish

The [complete fresh-host integration](2026-09-06-fresh-host-convergence-integration.md)
passed at commit `cc1069cbce87974a545095b3361b78837d618437`. It covers:

- first-install and later-update Home rollback in temporary homes;
- clean Nix installation, injected failure, timed uninstall, retry, and adoption;
- selected and unselected Tailscale, identity preservation, and root ownership;
- factory/headless transitions and persistent rollback across three container reboots;
- the real pilot's plan/apply/converge paths remaining exact no-ops.

Still to test on hardware: provisioning a second Spark and rebooting the pilot
in headless generation five. The Tailscale reboot test ran on generation four.

## What is not ready

| Area | Remaining work |
| --- | --- |
| General fleet customization | Broader users, package sets, and later root-generation updates |
| Desktop toggling | A retained-headless → GNOME operator and a full repeatable round trip |
| Remote desktop | Package/network checks, offscreen NVIDIA rendering, and short H.264/HEVC/AV1 NVENC tests passed. The first Hyprland capture attempt failed at KMS/backend startup. The root-readable KMS inspection passed; [one-boot trial tooling](nvidia-kms.md) is prepared but no KMS boot has occurred. Independent local recovery is required before the hardware trial. Real capture, input/audio, streaming, and sustained performance remain unproven. See [remote desktop](remote-desktop.md) |
| Ghostty | Real graphical runtime validation and activation |
| Hyprland | Non-NixOS NVIDIA graphics bridge, GDM session, and separate portal rollout |
| KDE | Package selection, host integration, and validation |
| Chromium | Exact root sandbox integration; no unsandboxed browsing workaround |
| Zed | Factory-GNOME Vulkan/portal checks and profile activation |
| LM Studio desktop | Resolve its vendor Electron sandbox fallback, then GB10/desktop validation |
| ChatGPT and 1Password extensions | Reproducible packaging/policy and migration from manual installs |
| Isaac/Omniverse | Exact workload pins, source/build plan, storage, and runtime validation |
| Other AI services | Choose the workload before adding models, ports, daemons, or containers |

See [configuration limits](configuration.md#current-limits) before assuming a
JSON option is an executable installation choice.

## Manual installs and retained fallback

Not everything outside the factory OS has completed its migration yet:

- ChatGPT desktop and the existing Firefox 1Password extension remain manual.
- Tailscale's apt package/source remains as inactive fallback; Nix owns the
  loaded unit and running daemon.
- The old standalone Codex release tree and `/usr/local/bin/devbox` remain as
  fallback material; the Nix-managed launchers win normal command resolution.
- GitHub CLI was used temporarily through Nix to publish this repository.
  It is not part of the fleet base. GitHub authentication is mutable local state.

These are documented exceptions, not an invitation to delete files. Cleanup
needs its own reviewed recovery plan.

## Where the truth lives

- Desired choices: [`fleet/hosts.json`](../fleet/hosts.json).
- Exact dependencies: [`flake.lock`](../flake.lock), package source records,
  and [Nix runtime metadata](../root/nix/release.json).
- Package readiness: [software manifest](software-manifest.md).
- Why: [decision register](decision-register.md).
- What happened: the dated [evidence index](README.md#evidence-worth-starting-with).
- What is true now: inspect the host through the current operator for its lifecycle.
