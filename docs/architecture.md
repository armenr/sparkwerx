# Architecture

## Decision

Retain NVIDIA DGX OS as a thin, vendor-managed substrate and use Nix for the
reproducible userland above it. Do not replace DGX OS with NixOS on the pilot.

## Why

The Spark's kernel, firmware, GB10 driver, CUDA integration, Docker runtime, and
recovery path are delivered and tested together by NVIDIA. Nix can manage most
interactive and development software without taking ownership of those pieces.

This yields two independent update tracks:

1. DGX Dashboard updates the vendor substrate during a maintenance window.
2. A reviewed `flake.lock` change updates reproducible userland packages.

Each track is validated on `sparkle-01` before wider rollout.

## Configuration composition

The desired configuration graph is:

`factory substrate -> exact CLI base -> host services -> desktop mode -> shared graphical role -> user overlay -> workload/project roles`

Each arrow is an explicit composition boundary. A desktop selection does not
select personal apps, a personal app does not start a server, and a workload
selection does not enable it at boot. The accepted choices and open decisions
live in the [decision register](decision-register.md).

## Managed by Nix

- Project development shells and individually approved project tools
- The exact fleet CLI base: `ncdu`, `lazydocker`, and `devbox`
- A shared graphical role containing Ghostty in every graphical mode
- Named user overlays, including Armen's personal graphical applications
- Switchable desktop roles and their user configuration after each pilot
- Host roles and per-host differences
- Host access services such as Tailscale after their reviewed migration
- Pinned workload definitions, wrappers, and validation commands

## Intentionally outside Nix ownership

- UEFI and device firmware
- Ubuntu/DGX OS, kernel, and NVIDIA driver
- CUDA and NVIDIA container runtime supplied by DGX OS
- DGX Dashboard and its update mechanism
- The initial Nix daemon installation
- Mutable Tailscale node identity and external tailnet policy, although their
  lifecycle and desired-state boundaries are documented here
- The minimal GDM/systemd/PAM integration required by a non-NixOS compositor

The last category remains version-controlled and idempotent even though it must
write into the host OS.

## Tailscale access plane

Tailscale is a repository-owned overlay, not factory substrate. The current
official apt package is retained only until an approved Nix package and root
service can take over without downgrading the daemon or replacing its mutable
identity. The locked Nixpkgs package is currently older than the installed
release, which is why a small official-artifact derivation may temporarily be
needed.

The service must remain wanted by `multi-user.target` in headless mode. Its
package, unit, and Tailscale SSH desired state are declarative; node identity
under `/var/lib/tailscale`, enrollment secrets, and tailnet access policy are
not Nix-store contents. The detailed rationale, audit fields, update path, and
rollback rules live in the
[Tailscale operations reference](../.agents/skills/dgx-spark-ops/references/tailscale.md).

## Desktop modes

A future root option selects exactly one of `headless`, `gnome`, `hyprland`,
or `kde`. Headless stops graphical services without removing the factory
desktop packages and must retain Tailscale. Graphical modes activate their
matching session and portal set plus the shared Ghostty terminal; Armen's
personal graphical overlay composes above that shared role. See the
[desktop-mode contract](desktop-modes.md).

## Hyprland pilot safety model

- GNOME and GDM remain installed and enabled.
- Hyprland is added as an alternate session, never as the only session.
- The first test is local and reversible.
- Host integration is applied separately from Home Manager.
- Rollback removes only repository-owned links/units and leaves GNOME intact.
- Display, suspend/wake, portals, screen sharing, Electron applications, and
  CUDA/container workloads must pass before enabling another Spark.

## Fleet shape

The flake will expose one Home Manager configuration per `<user>@<host>`. The
common permanent base contains exactly `ncdu`, `lazydocker`, and `devbox`.
Logical user overlays are mapped explicitly to those identities; `armen`
currently maps to `n0b0dy@sparkle-01` and is not a default for other users.
Only genuine hardware or role differences belong in `hosts/<hostname>/`.

Selected applications and workloads pass the
[pre-install software manifest](software-manifest.md) one at a time. Rollouts
use a pilot-first sequence rather than having each host independently follow an
unpinned channel.

## Current implementation hold

The existing `config.allowUnfree = true` and current
`modules/home/base.nix` package list predate the accepted policy. They are
documented provisional conflicts, not approved configuration. No Home Manager
activation may occur until a repository-only change adds exactly `ncdu`,
`lazydocker`, and a current Devbox pin; removes the old base packages; and
adds default-deny unfree handling, desktop/shared-graphical roles, and named
overlays.
