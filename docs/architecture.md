# Architecture

[Documentation](README.md) · [Decisions](decision-register.md)

Sparkwerx is a configuration layer **on DGX OS**, not a replacement operating
system. The purpose is to recreate the software we choose while leaving the
hardware-support stack with NVIDIA.

## Ownership

| Layer | Owner | How it changes |
| --- | --- | --- |
| Firmware, kernel, NVIDIA driver, system CUDA | NVIDIA DGX OS | Supported NVIDIA/DGX Dashboard updates |
| Docker engine, NVIDIA Container Toolkit, Dashboard packages | NVIDIA DGX OS | Vendor packages and update path |
| Nix bootstrap and runtime | Sparkwerx | Pinned installer plus a separate reviewed runtime update |
| User tools and selected settings | Nix + Home Manager | Exact package/profile generation |
| Tailscale package and service | Nix + System Manager when selected | Guarded host-service transition |
| Desktop runtime targets | Sparkwerx root controller | Guarded transition; factory GDM packages remain NVIDIA-owned |
| AI runtime definitions | Future independent workload roles | Exact Nix sources, container digests, or source-build pins |
| Credentials, models, account/application data | User or external storage | Explicit enrollment, backup, and retention—not Nix builds |

A component gets one active owner. A retained apt fallback is not a second
active service owner: inspect the loaded systemd fragment and running executable.

## How configuration fits together

```text
fleet/hosts.json                 flake.lock + package source records
        │                                      │
        └─────────── selected Nix graph ────────┘
                              │
             ┌────────────────┼──────────────────┐
             │                │                  │
        Home Manager    System Manager     Workload roles
        user profile    access + targets   selected/future
             │                │                  │
             └──────── NVIDIA DGX OS ────────────┘
                    kernel / GPU / runtime
```

The permanent Home base is ncdu, lazydocker, and Devbox. The named Armen
overlay adds Codex in all modes; Ghostty belongs to shared graphical profiles.
Desktop and workload selections don't silently enable personal applications,
API servers, model downloads, or autostart.

[`modules/home/fleet-host.nix`](../modules/home/fleet-host.nix) supplies the
generic user composition.
[`modules/system/fleet-host.nix`](../modules/system/fleet-host.nix) supplies
the generic root composition. Ordinary host additions use JSON; only genuine
host differences need [hosts](../hosts) overrides.

## Nix or containers?

Use the simplest reproducible route compatible with the factory GPU stack:

- **Native Nix:** CLI tools, configuration, launchers, development shells,
  and applications with a working ARM64 package.
- **Pinned containers:** vendor-tested CUDA/Python/framework combinations
  where rebuilding that dependency matrix adds risk without value.
- **Pinned source builds:** workloads whose Spark-supported route requires
  building from source, such as the selected Isaac work.

These choices can coexist. Nix can pin/configure a workload while a container
supplies its application userland. The host still supplies the kernel driver
and GPU device interface.

A tag such as `latest` is not an immutable image pin. Record the readable tag,
multi-architecture index digest, and resolved Linux ARM64 image digest.
Models, caches, databases, and outputs belong outside both the Nix store and
the image.

The [workload map](../.agents/skills/dgx-spark-ops/references/workload-map.md)
describes the researched options; it is not an installed-software list.

## Why two configuration managers?

Home Manager changes the user's environment. It cannot, by itself, stop
factory GDM, own a system daemon, or change the host's boot target.

System Manager gives specific Nix-defined system configuration to a non-NixOS
host. Sparkwerx restricts it to explicitly reviewed files and services.
Its defaults for users, wrappers, global packages/PATH, host Nix configuration,
and global tmpfiles processing are not adopted.

The pinned System Manager version has an exact-version patch preventing
empty managed tmpfiles rules from triggering processing of factory rules.
The [root runbook](../root/system-manager/README.md) explains the patch,
retention roots, and tests. Updating that manager is not a routine app refresh.

## Updates are separate transactions

- NVIDIA substrate updates.
- Nix provisioning-artifact updates.
- Nix runtime updates.
- User/package pin updates.
- Root service/desktop generations.
- Workload definitions and activation.

Stable Nixpkgs supports the user foundation; the apps input supplies selected
faster-moving packages. `nixpkgs-root` and System Manager preserve the proven
root graph independently. The user/package updater checks that graph has not
moved.

An installer version and a runtime version can legitimately differ. Devbox
triggered the original Nix installation, but it does not own Nix maintenance.
The [Nix runbook](../root/nix/README.md) also explains why the default
`upgrade-nix` candidate once proposed a downgrade.

## One fresh-host workflow, separate pilot history

A new host follows the [fresh-host lifecycle](fresh-host-convergence.md):
Nix → factory root generation → separate reboot → headless root generation →
Home. The command resumes after disconnects and verifies each phase.

The physical pilot reached its current state through five development
generations. Those are recovery/evidence anchors, not a template that each new
machine must replay. Both paths are tested, but their generation numbers,
guards, and status operators differ.

## Reproducibility is not backup

Git and Nix recreate declared software; they do not recreate your Tailscale
identity, browser sessions, chats, models, datasets, or training results.

Keep that data external, document its location, and design backup separately.
`/srv/dgx` is an intended storage convention, not an already provisioned
directory or a settled storage/backup policy.
