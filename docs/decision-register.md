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

The repository now pins and build-validates the official current-stable 1.102.3
ARM64 artifact plus a separately generated inert unit tree. That closes the
package/SBOM gate, not the ownership migration gate: apt remains live and no
daemon reload/restart or systemd link is authorized.

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

The apps pin supplies current dev-shell Git/ripgrep and exposes the reviewed
Zed, LM Studio, and Chromium candidates. Both current Nixpkgs branches still
trail Devbox at 0.17.5, so the fleet base uses a narrow exact override for the
current 0.18.0 source and Go vendor graph. Retire that adapter when stock catches
up and passes the same ARM64 checks. Candidate presence does not add a personal
application to Armen's overlay. Never replace the stable fleet package set
wholesale with unstable.

### D-013: Nix runtime updates are repository-reviewed root changes

**Status:** ACCEPTED

Nix is outside the factory substrate. The official NixOS `nix-installer`
provisioned it after Devbox triggered bootstrap, but Devbox does not own runtime
updates. Repository root artifacts and the dedicated audit own version
discovery, provenance, dry-run comparison, rollout, and rollback.

Never assume `nix upgrade-nix` means a semantic upgrade. Its default target is
a manually maintained Nixpkgs store-path file and the implementation has no
downgrade guard. At the 2026-08-23 checkpoint, the installer release is 2.35.1,
the default ARM64 fallback is 2.34.8, and final upstream stable is 2.35.2. The
default command is blocked.

Armen separately approved the checksum/cache-verified custom-path rollout on
the pilot. The active default profile and daemon now run Nix 2.35.2, while the
installer-created 2.35.1 environment remains an independent GC-rooted rollback
anchor. Future hosts and releases require the same separate authorization and
validation.

### D-014: System Manager is the bounded root-manager candidate

**Status:** SELECTED

Pin System Manager 1.1.0 from its matching `release-26.05` branch for a
non-NixOS pilot above the existing Ubuntu/DGX substrate. Selection authorizes
its repository definition and reviewed build/test gates, not host activation,
generation registration, or ownership of a service.

Upstream's nominally empty configuration enables broader defaults than this
fleet permits. The canary forces off Nix configuration ownership, users and
`userborn`, setuid wrappers, global packages and login PATH hooks, managed
tmpfiles, `/run/current-system`, and its boot-time target link. It declares
exactly one harmless `/etc/dgx-setup/canary` link, one no-network oneshot,
and System Manager's two control targets. No NVIDIA, Docker, Tailscale, GDM, or
desktop unit enters the graph.

System Manager's private engine wrapper is overlaid with the separately pinned
official Nix 2.35.2 release, matching the reviewed active host runtime. Closure
policy rejects stale Nix 2.34.8 and the otherwise-unused real `userborn`
binary. The built ARM64 canary is 109 paths / 230.0 MiB and has no global
package, port, boot link, or application state.

System Manager 1.1.0 otherwise invokes `systemd-tmpfiles --create --remove`
globally when its managed tmpfiles list is empty. The first disposable-container
activation exposed that boundary violation without touching the host. The
candidate therefore carries the exact-version `skip-empty-tmpfiles` patch
(SHA-256 `32756de30fd5730ebe60cce6ef89fc924ccd4eb3530e21ceb53fdf6073ba0e9a`),
and policy requires the patched manager, an empty managed-tmpfiles set, and no
global tmpfiles invocation. The test plants an unmanaged rule as a regression
sentinel. Any System Manager version change requires explicit patch
reassessment.

Low-level activation would create
`/var/lib/system-manager/state/system-manager-state.json`; deactivation empties
but does not remove that bookkeeping file. The canary test does not register
`/nix/var/nix/profiles/system-manager-profiles/system-manager` or
`/nix/var/nix/gcroots/system-manager-current`. Those registration paths remain
a separate gate.

Source inspection during the host preflight confirmed that low-level activation
also does not retain its store output. The host pilot therefore selects one
explicit direct root,
`/nix/var/nix/gcroots/dgx-setup-root-canary-pilot`, created only after the
same-window snapshot and before rollback is armed. It is not upstream generation
registration and does not replace that future decision. It must remain for the
entire active/rollback interval and may be removed only after verified
deactivation under separately explicit cleanup authority.

The patched runtime and closure-policy no-link builds passed. The exact
root-assisted disposable Ubuntu activation/deactivation derivation then passed,
including the unmanaged tmpfiles regression sentinel and clean host postflight.
Host activation still requires independent console access, collision review,
snapshots, exact store retention, timed rollback, and separate authorization.
This selection does not
advance the Tailscale migration or implement desktop-mode switching.

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

- Decide whether to authorize a System Manager host canary after independent
  console access, collision/snapshot evidence, exact pilot store retention, and
  a timed rollback procedure are in place.
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
  0.18.0; Devbox and Tailscale passed scoped no-link ARM64 builds;
- System Manager 1.1.0 is pinned as an inactive root-manager candidate; its
  109-path / 230.0 MiB canary and closure policy passed no-link builds with a
  private Nix 2.35.2 runtime and no real `userborn` closure; its exact patched
  disposable activation/deactivation test later passed on 2026-08-24 without
  host activation or registration;
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
host. The Tailscale package/unit and Devbox outputs are realized only in the Nix
store; Home Manager was not activated, the apt Tailscale daemon remains active,
and GDM/desktop state were not changed. The separately approved root Nix
runtime update to 2.35.2 completed and passed daemon, build, rollback-root, and
Tailscale-continuity checks. The software manifest remains the
application/service/desktop install and activation gate.
