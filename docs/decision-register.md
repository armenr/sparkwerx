# Decision register

This is the durable source of truth for choices made while designing the DGX
Spark fleet. It prevents a later session from reopening settled questions or
mistaking provisional scaffold code for approved policy.

## Status language

- **ACCEPTED** means the design is settled.
- **SELECTED** means software should be evaluated and packaged for its named
  scope.
- **OPEN** means a decision or validation gate remains.
- **NOT SELECTED** means do not add it unless Armen changes the decision.

None of these statuses authorizes a download, build, install, activation,
service restart, package removal, or host change. Those require a separate,
explicit request after the software manifest and rollback plan are reviewed.

## Accepted architecture

### D-001: preserve the factory substrate

**Status:** ACCEPTED

DGX OS, firmware, kernel, NVIDIA driver, system CUDA, Docker engine, NVIDIA
Container Toolkit, and DGX Dashboard remain NVIDIA-owned. This repository owns
only the reproducible layers above that substrate.

### D-002: keep a small, exact permanent fleet CLI base

**Status:** ACCEPTED

The Home Manager fleet base installs exactly `ncdu`, `lazydocker`, and
`devbox` for every managed fleet user. No other package enters the permanent
base without a new explicit decision. Repository-only tools can remain in the
development shell.

Installing `lazydocker` does not add the user to the Docker group or grant
access to the Docker socket. Installing the Devbox package does not authorize a
Devbox installer to install, replace, or update Nix; this repository retains the
Nix-runtime update procedure.

The base does not enable Home Manager's CLI, manpage plumbing, XDG base
directory management, shared MIME machinery, MIME defaults, desktop portals,
or graphical services. Those remain opt-in administrative, desktop,
shared-graphical, or user roles.

### D-003: default-deny unfree Nix packages

**Status:** ACCEPTED

Do not use global `config.allowUnfree = true`. Use an exact
`allowUnfreePredicate` only for selected packages that actually require it. A
free/unfree note exists only to make Nix evaluation and packaging behavior
explicit; this project does not maintain a license registry.

Current evidence says Chromium and Zed are free in locked Nixpkgs. LM Studio is
unfree; the apps package set permits only the exact Nix package name
`lmstudio`. The predicate installs nothing by itself. Any future ChatGPT
package is evaluated separately.

### D-004: compose independent layers

**Status:** ACCEPTED

Configuration composes in this order:

1. NVIDIA factory substrate
2. exact fleet CLI base
3. host services and access plane
4. exactly one desktop mode
5. shared graphical role when the mode is graphical
6. zero or more named user overlays
7. zero or more workload or project roles

A choice in one layer must not silently pull another layer in. In particular,
Hyprland does not imply its portal, a graphical user overlay does not imply a
desktop mode, and selecting an AI workload does not enable it at boot.

### D-005: use one switchable desktop mode

**Status:** ACCEPTED

The single option is:

`dgx.desktop.mode = "headless" | "gnome" | "hyprland" | "kde"`

Headless disables the graphical target, display manager, desktop session
services, portals, and graphical autostarts while retaining factory packages on
disk and keeping Tailscale available. GNOME means the factory Ubuntu desktop.
Hyprland and KDE are independently gated Nix-managed alternatives. GNOME stays
available as the local recovery session during graphical pilots.

The Home Manager profile-composition half is implemented. It currently controls
only user packages and user-level XDG ownership; it cannot stop GDM or change
the host target. The non-NixOS root controller, actual switch command, and
rollback implementation remain OPEN.

### D-006: keep Armen's tools in a personal overlay

**Status:** ACCEPTED

The logical overlay is named `armen`. On the pilot it maps explicitly to
`n0b0dy@sparkle-01`; future hosts must declare their own mapping. It is never
part of the fleet base and is never inherited by another user merely because
that user exists on the host.

Graphical pieces of the overlay are inactive in headless mode.

### D-007: Ghostty is the shared graphical terminal

**Status:** SELECTED

Ghostty belongs to the shared graphical role and is available in GNOME,
Hyprland, and KDE. It is not part of the permanent CLI base, Armen's personal
overlay, or the active headless profile. It has no default autostart.

### D-008: personal graphical software selections

**Status:** SELECTED

Armen's graphical overlay contains these intended items:

- ChatGPT desktop application
- Chromium
- 1Password extension for Firefox
- 1Password extension for Chromium
- Zed editor
- LM Studio desktop application

They are selected for packaging, inventory, and validation one at a time. They
are not yet approved for installation or activation. No application is enabled
for autostart by default.

### D-009: Isaac/Omniverse is a separate DGX workload

**Status:** SELECTED

Create a future `isaac-omniverse` workload role for Isaac Sim, Isaac Lab,
and the Omniverse platform/tooling Armen wants for robotics and simulation.
Follow the current NVIDIA DGX Spark Isaac playbook as the first validated path,
then itemize and pin each additional Omniverse application or Kit component
before adding it.

This selection does not authorize every product in NVIDIA's catalog, and it
does not select NIM or NVIDIA AI Enterprise. Isaac/Omniverse remains separate
from Armen's personal desktop overlay.

### D-010: Tailscale is a managed access overlay

**Status:** ACCEPTED

Tailscale and Tailscale SSH are outside the factory substrate and will move from
the current official apt installation to reviewed Nix/root-service ownership.
The migration must preserve node identity and remote access and must keep
`tailscaled.service` available in headless mode. The dedicated Tailscale
reference controls this work.

### D-011: Nix and containers are complementary

**Status:** ACCEPTED

Use Nix for reproducible tools, configuration, wrappers, development shells,
source pins, and well-supported native ARM64 packages. Use pinned containers or
vendor source-build workflows when NVIDIA validates a coupled CUDA/Python
runtime that should not replace the factory GPU stack. Models and mutable
application state stay outside the Nix store and container images.

### D-012: keep stable foundations and fast-moving apps on separate pins

**Status:** ACCEPTED

Use the stable `nixos-26.05` Nixpkgs input for the fleet foundation, Home
Manager, the base tools that are current there, and shared infrastructure. Use
the independently locked `nixpkgs-apps` input only for reviewed fast-moving
applications whose stable package trails the current release.

The first such package is Devbox 0.17.5. The same apps pin currently exposes the
reviewed Zed, LM Studio, and Chromium candidates, but their presence in the
package set does not add them to Armen's overlay or authorize a build. A future
update reviews both inputs separately; never replace the stable fleet package
set wholesale with unstable.

## Explicit non-selections

| Item | Decision |
| --- | --- |
| Visual Studio Code | NOT SELECTED. Use Zed. Do not add VS Code through a playbook, package, role, recommendation, or transitive convenience bundle. |
| NVIDIA NIM | NOT SELECTED. Do not scaffold or deploy it. |
| NVIDIA AI Enterprise | NOT SELECTED. Do not add its tooling, entitlement flow, or deployment stack. |
| Google Chrome | NOT SELECTED at present. Chromium is the selected browser. |
| 1Password desktop application | NOT SELECTED at present. Only the two browser extensions are selected. |
| LM Link | NOT SELECTED at present. Tailscale access already exists; evaluate LM Link separately if requested. |

## Open decisions

- Choose and validate the non-NixOS root configuration manager.
- Design the exact systemd/GDM implementation and rollback for all four desktop
  modes.
- Decide whether KDE is merely supported as a mode or actually selected for
  installation on a host.
- Complete one-at-a-time package wiring and validation for the pinned Chromium,
  Zed, and LM Studio candidates.
- Choose reproducible package/update paths for ChatGPT and both browser
  extensions.
- Decide whether the already-installed Codex CLI moves into Armen's overlay or
  another role.
- Decide whether headless `llmster` is wanted as an independent serving
  workload; selecting the LM Studio desktop app did not select the daemon.
- Approve the persistent workload/model storage root and backup policy.
- Approve each workload's model choices, ports, service enablement, and
  scheduling independently.

## Phase 1 implementation checkpoint

The repository-only policy alignment was completed and evaluated on
2026-08-23:

- global unfree permission is gone; stable denies all unfree packages and the
  apps set permits exactly `lmstudio`;
- the permanent role is exactly current `ncdu`, `lazydocker`, and Devbox
  0.17.5;
- Home Manager CLI, the man viewer/manual, XDG base directories, shared MIME
  support, MIME defaults, user directories, and portals have separate gates;
- all four desktop enum values evaluate, Ghostty is shared-graphical only, and
  the Hyprland portal is independently gated;
- `armen` maps explicitly to `n0b0dy@sparkle-01`, persists while headless, and
  has no application packages wired yet; and
- evaluation invariants and dry-run plans cover headless, GNOME, Hyprland, and
  Hyprland-with-portal.

The exported pilot Home profile remains staged as user-layer `headless` for the
future exact-base activation. This does not change the running factory GNOME
host. No Phase 1 work built a new package output, activated Home Manager,
changed GDM/systemd, or changed a service. The software manifest remains the
build/install approval gate.
