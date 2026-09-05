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

Current evidence says Chromium and the selected official Zed package are free.
LM Studio is unfree; the apps package set permits only the exact Nix package
name `lmstudio`, including the current direct vendor-artifact adapter. The
predicate installs nothing by itself. Any future ChatGPT package is evaluated
separately.

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

The current Chromium 152.0.7977.75, direct Zed 1.18.0, and direct LM Studio
0.4.23-1 ARM64 packages have passed their build and closure-policy gates but
remain outside every Home profile. Chromium requires an exact graphical root
sandbox role because its store helper cannot be setuid and Ubuntu AppArmor
blocks its user-namespace fallback; `--no-sandbox` and global user-namespace
relaxation are rejected. Zed still requires factory-GNOME Vulkan/portal
validation. LM Studio additionally requires an explicit decision on its vendor
Electron `--no-sandbox` fallback; this repository will not weaken the host
AppArmor policy silently.

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
`tailscaled.service` available in headless mode whenever the host selects the
access role. Tailscale is an explicit optional per-host role, not an implicit
dependency of the fleet base or every machine. The dedicated Tailscale
reference controls this work.

The repository now pins and build-validates the official current-stable 1.102.3
ARM64 artifact plus the root unit. Its exact apt-to-Nix transaction,
injected-failure rollback, candidate/vendor reboots, and persistent
unconfirmed-reboot rollback pass in a disposable container. The guarded live
operator requires a clean commit, private snapshot, console recovery, rollback
before mutation, a separately authorized real reboot, and a fresh connection
before confirmation. Apt remains live; this evidence does not itself authorize
the daemon restart or systemd ownership change.

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

The live System Manager closure and its exact test evidence use a third,
immutable `nixpkgs-root` input at the already-proven stable revision. Routine
dependency updates exclude both that input and System Manager and must prove
their complete root fingerprint unchanged before continuing. Advancing the
root lane is a separate root-generation workflow, not a user-package refresh.

The apps pin supplies current dev-shell Git/ripgrep and Chromium plus the stock
comparison packages for Zed and LM Studio. Exact official ARM64 adapters pin
current Zed 1.18.0 and LM Studio 0.4.23-1 because the locked stock packages
trail those releases. Both current Nixpkgs branches also trail Devbox at 0.17.5,
so the fleet base uses a narrow exact override for the current 0.18.0 source and
Go vendor graph. Retire each adapter when stock catches up and passes the same
ARM64 checks. Candidate presence does not add a personal application to Armen's
overlay. Never replace the stable fleet package set wholesale with unstable.

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
as recovery anchors. At design time this granted no live-switch authority and
no permission to clean up either root. See the
[live plan](../root/system-manager/validation/2026-09-02-generation-switch-live-plan.md).

Armen later created fresh private snapshot `20260902T083437Z`, verified the
local console, and explicitly authorized that exact snapshot. The guarded
wrapper retained, registered, selected, and activated generation two, repeated
postflight, and disarmed rollback without its service running. Read-only
postflight classified the host
`ACTIVE_REGISTERED_GENERATION_TWO_RETAINED`: generation two is selected,
upstream-rooted, directly retained, and live; generation one remains registered
and directly retained. Both pilot roots remain, protected services and
Tailscale SSH stayed healthy, and no boot edge or broader ownership appeared.
The spent snapshot grants no authority to rerun the wrapper, roll back, clean
up a root or generation, or reboot. See the
[retained generation-two record](../root/system-manager/validation/2026-09-02-generation-switch-host-attempt-1.md).

Boot persistence is now an explicit opt-in System Manager role, disabled by
default. Exact generation three inherits generation two and changes only its
identity marker plus the tracked
`default.target.wants/system-manager.target -> ../system-manager.target` edge.
It keeps the global package set empty, the three managed service definitions
identical, `system-manager.linkCurrentSystem = false`, and every factory,
access, NVIDIA, desktop, Nix, user, wrapper, PATH, port, and mutable-state
boundary unchanged.

The exact generation-two to generation-three transaction passed a distinct
13-subtest/two-restart disposable `systemd-nspawn` derivation on 2026-09-02.
It proved unretained-candidate and collision refusal, rollback after partial
registration and post-activation failure, exact apply, automatic start after a
fresh container start, rollback to generation two, no automatic start after a
second fresh start, and complete disposable cleanup. Independent host
postflight remained `ACTIVE_REGISTERED_GENERATION_TWO_RETAINED`; the host
generation-three pilot root and boot edge remained absent. See the
[boot-persistence transaction plan](../root/system-manager/validation/2026-09-02-boot-persistence-transaction-plan.md)
and exact
[container-test result](../root/system-manager/validation/2026-09-02-boot-persistence-transaction-container-test.md).

That PASS selected the declarative mechanism and authorized design of a guarded
live pilot only. The resulting exact snapshot helper and activation wrapper
were hash-pinned with clean-commit, exact-generation-two, fresh-private-snapshot,
unchanged-process, independent-console, rollback-before-activation,
repeated-postflight, and exact-`KEEP GENERATION THREE` gates.

Armen later created fresh snapshot `20260902T110421Z`, verified the physical
console, and explicitly authorized that exact snapshot without authorizing a
reboot. The wrapper retained, registered, selected, and activated generation
three, installed only the declarative boot edge, passed postflight twice, and
disarmed rollback before its service ran. Independent audit classified the host
`ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED`: generations one,
two, and three plus all three direct roots remain exact; generation three is
selected/upstream-rooted/live; the version-1 state is six paths/three services;
and protected services, GPU, and Tailscale SSH are healthy. Snapshot
`20260902T110421Z` is spent.

Live activation and the first real reboot were distinct gates. After the live
activation, the separately authorized persistent recovery survived the first
real reboot. The ten-minute confirmation deadline expired, so automatic
rollback restored exact registered/live no-boot generation two; subsequent
snapshot-bound verification and exact recovery cleanup passed. All three
direct pilot roots remained. The first restoration attempt then safely timed
back after a mistyped retention phrase. Its retry-safe replacement used one
Enter, passed two full postflights, and automatically retained exact registered/
live/boot-linked generation three without rebooting. All three numbered
generations and direct roots remain; generation three is selected and
upstream-rooted, the one declarative boot edge exists, the recovery surface is
absent, and no timer is armed. The postboot health gate recognizes Nix's normal
idle daemon behind its active socket, and a short operator router removes
fragile private-snapshot paths while still exposing no reboot action. See the
[guarded live activation plan](../root/system-manager/validation/2026-09-02-boot-persistence-live-plan.md).
The recovery design and exact result are in the
[persistent recovery plan](../root/system-manager/validation/2026-09-02-reboot-recovery-transaction-plan.md)
and
[container-test result](../root/system-manager/validation/2026-09-02-reboot-recovery-transaction-container-test.md).
The original live sequence is in the
[live recovery plan](../root/system-manager/validation/2026-09-03-reboot-recovery-live-plan.md).
The real reboot record remains recovery authority; the current live-state
authority is the
[successful restoration record](../root/system-manager/validation/2026-09-03-restoration-host-attempt-2.md).

### D-015: one declarative fresh-host workflow

**Status:** ACCEPTED

The intended operating experience for another factory DGX is: complete NVIDIA
updates, clone this repository, declare the host and user role selections,
review one exact plan/SBOM, apply through one guarded entry point, and continue
working. A new machine must not require replaying `sparkle-01`'s manual
discovery or hand-installing selected optional software.

The host declaration composes the exact common base with explicit optional
access roles such as Tailscale, one desktop mode, named user overlays,
developer-tool roles, and workload roles. Planning and application remain
separate operations. The apply path must preserve the factory substrate,
retain the previous generation, reject unknown drift, and run role-specific
health/rollback checks.

Nix is the bootstrap exception: a pristine machine needs a small,
checksum-pinned, idempotent install-or-adopt step before Nix can manage the
remaining layers. Tailscale identity, browser/account state, secrets, models,
and other mutable data remain outside the Nix store even when Nix owns their
packages, units, and declarative settings.

Implemented on 2026-09-03: `fleet/hosts.json` is the schema-validated selection
surface; `bootstrap/nix/source.json` pins the official ARM64 installer and
planner inputs; and `scripts/dgx-setup plan` renders the local declaration,
bootstrap adoption/install classification, exact Home candidate/live state,
and remaining role gates without applying them. Its host test proves unknown
hosts fail, the serial is never emitted, Home/profile links remain exact, and
protected service processes/fragments do not change. Nix evaluation may fetch
missing locked flake sources.

The bootstrap subcommand now verifies and adopts the exact healthy pilot with
zero mutation. Its clean-host branch is implemented around the same pin: it
validates the official plan, arms receipt-driven rollback before installation,
advances to the separately pinned runtime, verifies systemd/GPU/access
continuity, and disarms automatically. Its exact disposable Ubuntu lifecycle
passed on 2026-09-03: injected post-runtime failure rolled back to the clean
boundary, a clean retry reached exact Nix 2.35.2 with persistent flakes, and a
second run adopted without mutation. The Nix-only branch is eligible for a
declared clean ARM64 host through the one repository operator.

The staged guarded `scripts/dgx-setup apply` entry point now composes that exact
bootstrap with the proven headless Home first-activation/update lifecycle. The
original live pilot regression passed with both layers as exact no-ops. After
the separately guarded Tailscale migration, the front door also verifies the
already Nix-managed generation-four access role without restarting it. It
reports `APPLY_STATUS=PARTIAL` because the root desktop controller remains OPEN
and untouched. This is deliberately not a false claim of complete desired-state
convergence; the integrated clean-host path and each optional ownership layer
retain their own gates.

### D-016: Codex is an Armen-only all-modes tool with unrestricted defaults

**Status:** ACCEPTED

Every Codex session for Armen defaults to `approval_policy = "never"` and the
built-in `:danger-full-access` permission profile. Eligible approval review and
app-tool defaults use automatic review/approval, and destructive/open-world app
tools are enabled by default. Armen explicitly accepts that these settings let
Codex access the full machine and network and execute without approval pauses.

This belongs to Armen's non-graphical personal overlay, so it applies in
headless, GNOME, Hyprland, and KDE modes without entering the exact fleet base
or affecting another user. The overlay owns the exact current official ARM64
Codex release bundle and the higher-precedence `~/.local/bin/codex` launcher.
Its standalone updater is disabled because the repository's checksum-verifying
`scripts/update-codex.sh` owns release discovery and pin changes.

Home Manager also invokes a narrow, idempotent reconciler that owns only these
approval/permission and Nix-update keys and preserves the rest of mutable
`~/.codex/config.toml`. It refuses symlinks and foreign-owned files. The live
pilot config has the permission settings and passes strict Codex parsing. The
Nix package and higher-precedence launcher are active through retained Home
generation one; the 0.152.0 standalone release tree remains rollback input but
no longer wins command resolution.

### D-017: Tailscale service ownership is Nix-managed; apt is retained fallback

**Status:** ACCEPTED AND ACTIVE ON `sparkle-01`

Exact current-stable ARM64 Tailscale 1.102.3 and its `tailscaled.service` are
owned by System Manager generation four. The guarded handoff preserved the
existing `/var/lib/tailscale` identity and `RunSSH=true`, survived the expected
SSH disconnect, passed one real reboot, and was confirmed only after a fresh
Tailscale SSH connection and repeated health checks. The migration rollback
guard is gone and no timer is armed.

The apt package and repository remain installed but do not own the loaded unit
or running daemon. They are deliberate rollback material, not configuration
drift. Removing that fallback is a separate reviewed cleanup and is not part of
ordinary `plan`, `apply`, or dependency updates. The current authority is
[host attempt 2](../root/tailscale/validation/2026-09-05-host-attempt-2.md).

### D-018: desktop modes use thin targets and never own factory GDM

**Status:** ACCEPTED AS BUILT CANDIDATES; NOT ACTIVE

The first root desktop controller supports only `headless` and factory `gnome`.
It adds two mutually exclusive, isolatable systemd targets. The headless target
requires both Ubuntu's `multi-user.target` and `system-manager.target`; the
GNOME target requires factory `graphical.target` and `system-manager.target`.
This keeps Nix-managed Tailscale alive during either mode without relying on an
apt-era enablement link.

The selected mode supplies an immutable `/etc/systemd/system/default.target`
dispatcher plus a non-secret marker. The dispatcher explicitly requires the
selected named mode target because System Manager cannot safely emit a normal
systemd alias to an immutable store path. Neither candidate declares, replaces,
masks, or packages GDM, `display-manager.service`, GNOME, or an XDG portal.
Removing the controller removes the `/etc` default override so Ubuntu's
original `/usr/lib/systemd/system/default.target -> graphical.target` is
authoritative again.

System Manager activation changes persistent declaration only. Runtime target
isolation—which can terminate a GUI session—belongs to a separate guarded
operator with explicit preview, rollback, and postflight. The exact candidates
and static checks are recorded in the
[desktop-controller candidate record](2026-09-05-desktop-controller-candidates.md).
They grant no live switch or reboot authority.

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

- The first recovery reboot/rollback and later Tailscale reboot/retention are
  proven. Generation four is selected/upstream-rooted/live/boot-linked, all
  four numbered generations and direct pilot roots remain, and recovery is
  clean and unarmed. Any later recovery arming, reboot, or generation/pilot-root
  retirement remains a separate decision.
- Pass the disposable headless/factory-GNOME lifecycle and build its guarded
  live switch/rollback operator. Hyprland and KDE remain later independent
  extensions.
- Decide whether KDE is merely supported as a mode or actually selected for
  installation on a host.
- Design and prove Chromium's exact root sandbox integration, then wire and
  graphically validate the pinned Chromium, Zed, and LM Studio candidates. All
  three package/policy builds are complete; their factory-GNOME GPU/portal/
  runtime gates remain open.
- Choose reproducible package/update paths for ChatGPT and both browser
  extensions.
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
  carries the current Codex package in every mode. Its graphical apps remain
  absent from all profiles; exact current Chromium, Zed, and LM Studio
  candidates are separately built and documented; and
- evaluation invariants and dry-run plans cover headless, GNOME, Hyprland, and
  Hyprland-with-portal.

At that Phase 1 checkpoint, the exported pilot Home profile was active as
retained user-layer `headless` generation one. This did not change the running
factory GNOME host. Devbox was active through the Nix user profile; Tailscale
was still candidate-only and apt-owned. D-017 and its live evidence supersede
that historical Tailscale state. GDM/desktop state remains unchanged. The
separately approved root Nix
runtime update to 2.35.2 completed and passed daemon, build, rollback-root, and
Tailscale-continuity checks. The software manifest remains the
application/service/desktop install and activation gate.

The first headless activation used `scripts/dgx-home`: a clean-commit,
private-snapshot transaction with a ten-minute automatic user rollback and no
typed confirmation phrase. Headless disables Home Manager's user-systemd layer,
removing its generic `tray.target`, environment file, and reload phase. The
exact 52-path candidate, collision audit, dry run, disposable rollback, real
rollback, and fresh retained reactivation are recorded in the
[preflight](2026-09-03-home-headless-preflight.md) and
[host result](2026-09-03-home-headless-host.md).

Later headless package revisions use `scripts/dgx-home update-headless`. The
command is deliberately idempotent when Git and the live generation match. For
a distinct committed candidate it requires the exact recorded live state,
retains both candidate outputs, snapshots the profile/GC-root inventories,
arms a ten-minute rollback before activation, keeps the prior generation, and
passes two postflights before disarming. Its disposable completed and
partial-transition rollback tests passed without touching the real profile. A dependency-review
commit may expose `currentCandidate != observedCandidate`; that is a reviewable
`UPDATE_AVAILABLE` state, not flake-evaluation failure. A successful real
update must be followed by a deployment-evidence commit before another update.
See the [update lifecycle](2026-09-03-home-headless-update-lifecycle.md).
