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

Three separately authorized live canaries have proved the exact
five-path/three-service boundary. Attempts 1 and 2 failed closed for a verifier
defect and a missing exact human confirmation, respectively; both timed
rollbacks completed successfully. Attempt 3 on 2026-09-01 passed corrected
postflight twice, independent local-console confirmation, and independent
read-only postflight, then disarmed rollback. The exact canary is currently
active and directly retained by the pilot root. At that activation milestone,
no generation was registered, no boot link existed, and no broader root role
was active.

The next selected design milestone was generation registration and switching,
not a real service. The exact disposable lifecycle derivation passed on
2026-09-01. It proved partial-registration behavior, two generations, profile
selection versus activation, extra-GC-root synchronization, rollback
activation, deactivation with retained history, protected-file preservation,
and the existing tmpfiles boundary. Independent postflight found the retained
host canary unchanged and all host registration paths absent. This pass
authorizes design of the live registration/rollback transaction only. It does
not authorize live registration, boot linkage, Tailscale migration, desktop
switching, or pilot-root removal.

The exact first-generation transaction and its distinct failure-injection
container derivation passed on 2026-09-01. All nine preflight, upstream partial
failure, fail-closed cleanup, successful registration, idempotent rollback, and
disposable cleanup scenarios completed against the exact reviewed transaction
checksum. The prior two passed derivations remained unchanged. Independent
postflight found the host still `ACTIVE_RETAINED`, unregistered, not
boot-linked, and healthy. This pass makes the exact live SBOM and rollback gate
eligible for review; it did not authorize the live wrapper. The later live
registration still required a clean committed tree, same-window root-owned
snapshot, independent console, armed ten-minute rollback, and authorization
bound to the fresh snapshot.

The first live wrapper invocation on 2026-09-01 passed its snapshot gate and
then failed closed before mutation on a false `nix-daemon.service` `MainPID`
comparison. The wrapper's snapshot parser had assumed property order within
multi-unit `systemctl show` output and crossed into the next unit record when
`MainPID` preceded `Id`. No rollback unit, profile generation, or extra root
was created; postflight found `ACTIVE_RETAINED` with the complete registration
surface absent. The corrected parser handles each unit record atomically and
passed synthetic plus all-seven-unit regression checks. The transaction
checksum and disposable derivations are unchanged. The old commit-bound
snapshot is retired; retry requires a new clean commit, snapshot, console
check, and exact snapshot-bound authorization.

Attempt 2 then refused an otherwise valid snapshot at 2,207 seconds old,
before timer or mutation, and clean postflight again found `ACTIVE_RETAINED`
with registration absent. Attempt 3 used corrected commit `0f03d01` and fresh
snapshot `20260901T201613Z`. It passed the complete preflight, armed the exact
registration-only rollback, registered generation one and the upstream extra
root without activation, passed postflight, received exact
`KEEP REGISTRATION` confirmation after independent console verification,
passed repeated postflight, and disarmed rollback before its service ran.
Independent postflight classified the host `ACTIVE_REGISTERED_RETAINED`. The
registered generation, upstream extra root, and pilot root all resolve to the
exact candidate; no boot link or broader ownership exists.

The repository-only design introduced a generation-two candidate whose
only delta is the harmless canary marker plus an exact guarded switch/rollback
transaction. Its distinct eleven-subtest failure-injection container derivation
passed with a hash-valid output and clean host postflight. Generation one
remains exact registered/live state, the host generation-two root remains
absent, and no boot link or factory/access service changed. This grants
authority to design the separate live wrapper only; it grants no live-switch
authority. See the
[generation-switch transaction plan](../root/system-manager/validation/2026-09-02-generation-switch-transaction-plan.md)
and exact
[container-test result](../root/system-manager/validation/2026-09-02-generation-switch-transaction-container-test.md).

The subsequent repository milestone added a root-only private snapshot helper,
whole-record systemd property parser plus regression test, and a guarded live
wrapper. The wrapper creates the generation-two pilot root only after exact
preflight, arms the tested generation-one rollback before switching, requires
exact `KEEP GENERATION TWO` after local-console verification, and repeats full
postflight before disarming. Rollback removes only the exact generation-two
profile link and restores registered/live generation one; both pilot roots stay
as recovery anchors. This design is pinned and unrun. It creates no live-switch
authority and no permission to clean up either root. See the
[live plan](../root/system-manager/validation/2026-09-02-generation-switch-live-plan.md).

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

- The live generation-two pilot is designed but still needs a fresh private
  snapshot, local-console verification, and explicit snapshot-bound
  authorization. The live switch, reboot/boot behavior, pilot-root retirement,
  and the first real managed service remain separate decisions. Registration is
  not activation or boot persistence; do not reboot or add boot linkage without
  a separately guarded plan.
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
- System Manager 1.1.0 was pinned as an inactive root-manager candidate; its
  109-path / 230.0 MiB canary and closure policy passed no-link builds with a
  private Nix 2.35.2 runtime and no real `userborn` closure; its exact patched
  disposable activation/deactivation test passed on 2026-08-24, its third
  guarded host attempt was retained on 2026-09-01, and the exact disposable
  generation-registration lifecycle test then passed without host registration
  or boot linkage; the exact guarded first-generation failure-injection test
  then passed with clean host postflight; the first live registration wrapper
  attempt later failed closed before mutation because of an order-dependent
  service-snapshot parser, which was corrected and regression tested; a second
  attempt refused an expired snapshot before mutation, and the third retained
  exact generation one after repeated postflight and local-console
  confirmation while activation remained unchanged and no boot link appeared;
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
