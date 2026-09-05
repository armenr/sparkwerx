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

## Fresh-host contract

The target operator experience is: update a factory DGX through NVIDIA's
supported path, clone this repository, declare the host/user role selections,
review one complete plan/SBOM, apply it through one guarded entry point, and
carry on. Adding another Spark should not require replaying this pilot's manual
discovery or hand-installing optional software.

The machine-readable `fleet/hosts.json` declaration now composes the exact base
with explicit choices:

- optional host/access roles such as Nix-managed Tailscale;
- exactly one `dgx.desktop.mode`;
- optional shared graphical software;
- named user overlays such as `armen`;
- optional developer-tool roles, including the current Codex CLI package in
  Armen's all-modes overlay alongside its declared permission policy; and
- independently selected workload roles.

The `scripts/dgx-setup plan` front door implements the non-applying half. It
validates the declaration using only factory Python, classifies the pinned Nix
bootstrap, and—when Nix exists—evaluates the exact Home candidate and live
drift. Nix evaluation may fetch absent locked sources, but the plan does not
build/install packages, mutate profiles, change services, enroll Tailscale,
switch desktops, or reboot. The staged `scripts/dgx-setup apply` half now
composes the independently proven Nix bootstrap/adoption and headless Home
lifecycle, refusing unsupported host or declaration drift before mutation and
using each layer's own retention, health, and rollback checks. It also verifies
the already Nix-managed Tailscale role without restarting it. It reports
`APPLY_STATUS=PARTIAL` while the root desktop controller remains an explicit
untouched hold. Secrets, browser/account state, Tailscale node
identity, models, and other mutable data remain external inputs rather than
Nix-store contents.

Nix itself is the unavoidable bootstrap exception on a pristine host. Its
official ARM64 installer release, URL, size, hash, planner inputs, and desired
runtime are now plain-JSON repository inputs with a verified updater and plan.
The executable operator adopts the exact healthy pilot as a no-op and contains
a clean-host install path with validated official plan, rollback-before-mutation,
exact runtime update, and systemd/GPU/access continuity postflight. The adoption
path is host-tested, and the exact clean install, injected-failure rollback,
clean retry, and second-adoption lifecycle passed in disposable Ubuntu on
2026-09-03. Once adopted, Nix version/update/rollback ownership belongs to this
repository. The guarded configuration apply orchestrator is implemented for
the Nix and headless Home stages; complete optional-role convergence is not yet
implemented.

## Managed by Nix

- Project development shells and individually approved project tools
- The exact fleet CLI base: `ncdu`, `lazydocker`, and `devbox`
- A shared graphical role containing Ghostty in every graphical mode
- Named user overlays, including Armen's personal graphical applications
- Switchable desktop roles and their user configuration after each pilot
- Host roles and per-host differences
- Bounded System Manager root integration after its isolated and host pilot
  gates
- Host access services such as Tailscale after their reviewed migration
- Pinned workload definitions, wrappers, and validation commands

The stable Nixpkgs input remains the Home Manager and fleet-package foundation.
A separately locked apps input is consumed narrowly for reviewed fast-moving
packages. The live System Manager closure and its test evidence use an exact
`nixpkgs-root` revision that routine user/package updates cannot advance.
Exact current-release adapters cover Devbox and Tailscale only while both
package sets lag; they do not replace the fleet package set wholesale and must
be retired when stock catches up.

## Intentionally outside Nix ownership

- UEFI and device firmware
- Ubuntu/DGX OS, kernel, and NVIDIA driver
- CUDA and NVIDIA container runtime supplied by DGX OS
- DGX Dashboard and its update mechanism
- Nix's own initial installation transaction; the repository pins and plans it,
  but an absent Nix cannot perform it
- Mutable Tailscale node identity and external tailnet policy, although their
  lifecycle and desired-state boundaries are documented here
- The minimal GDM/systemd/PAM integration required by a non-NixOS compositor

The last category remains version-controlled and idempotent even though it must
write into the host OS.

## Root-manager pilot

System Manager 1.1.0 on its matching `release-26.05` branch is the selected
candidate for small non-NixOS root integration. Its base repository canary is
intentionally narrower than upstream's empty defaults: no host Nix ownership,
users, wrappers, global packages/PATH, tmpfiles, `/run/current-system`, boot
link, port, or factory/Tailscale/desktop unit. Its private engine uses exact Nix
2.35.2 so the root closure cannot reintroduce the stale 2.34.8 runtime.

The built canary owns only `/etc/dgx-setup/canary`, a no-network oneshot, and
System Manager's two control targets. Low-level activation leaves its rollback
record under `/var/lib/system-manager/state`; registration/profile roots are a
separate action, and low-level activation does not otherwise retain its store
closure. The pilot therefore keeps the direct root
`/nix/var/nix/gcroots/dgx-setup-root-canary-pilot`. That exact canary became
registered/live/boot-linked generation three after the first real reboot's
verified automatic rollback and the later verified restoration. It is now the
inherited foundation of generation four, which adds the Nix-managed Tailscale
service. All four generations remain registered and directly retained by their
pilot roots. The foundational six disposable tests and guarded live activation,
registration, generation-switch, boot-link, and first-reboot milestones passed.
Generation three differs from generation two only by its marker and one
declarative `default.target` edge; its activation used a fresh private snapshot,
protected-process continuity, an armed ten-minute rollback, repeated
postflight, and local-console confirmation. No broader role exists. Persistent
recovery then survived a real host reboot and restored exact generation two
when the confirmation deadline expired; verification and exact cleanup
passed. Restoration attempt one safely exercised its own rollback; retry-safe
attempt two passed two postflights and automatically retained generation three.
The later Tailscale migration and guarded reboot retained generation four.
Hash-pinned lifecycle helpers accept Nix's normal postboot socket-idle state,
and short operator routers avoid long private paths. The host is unarmed.
Read
[the root-manager runbook](../root/system-manager/README.md) before evaluating,
testing, registering, or activating it.

## Tailscale access plane

Tailscale is a repository-owned overlay, not factory substrate. The official
current-stable ARM64 package and unit are exactly pinned, no-link built, and
SBOM-reviewed. Exact System Manager generation four now owns the loaded unit
and running daemon without replacing its mutable identity. Locked stable/apps
packages remain older. The apt package and repository remain installed only as
inactive fallback material.

The exact migration transaction and persistent rollback bundle now pass a
disposable lifecycle covering failure after registration, Nix takeover, Nix
reboot, explicit vendor rollback, vendor reboot, and automatic rollback after
an unconfirmed candidate reboot. The live migration then survived the expected
SSH disconnect, fresh reconnect, one guarded real reboot, and another fresh
Tailscale SSH connection before confirmation. `scripts/dgx-tailscale` remains
the reviewed status and migration entry point for this fleet.

The service must remain wanted by `multi-user.target` in headless mode. Its
package, unit, and Tailscale SSH desired state are declarative; node identity
under `/var/lib/tailscale`, enrollment secrets, and tailnet access policy are
not Nix-store contents. The detailed rationale, audit fields, update path, and
rollback rules live in the
[Tailscale operations reference](../.agents/skills/dgx-spark-ops/references/tailscale.md).

## Desktop modes

The implemented Home Manager enum selects exactly one of `headless`, `gnome`,
`hyprland`, or `kde` for user-profile composition. The first root-controller
candidates now apply `headless` and factory `gnome` through thin, mutually
exclusive targets. Each target requires `system-manager.target`, so an isolate
cannot discard Nix-managed Tailscale; neither candidate owns GDM or a desktop
package. Their selected immutable `default.target` alias overrides the factory
default only while the role is active, and activation alone never performs the
runtime isolate.

These candidates are built and statically checked but not live. Headless will
stop graphical services without removing factory packages after the disposable
lifecycle and guarded switch gates pass. Later graphical modes activate their
matching session and portal set plus the shared Ghostty terminal; Armen's
personal graphical overlay composes above that shared role. The current pilot
Home profile is user-layer headless while the actual host remains in factory
GNOME. See the [desktop-mode contract](desktop-modes.md) and
[candidate record](2026-09-05-desktop-controller-candidates.md).

## Hyprland pilot safety model

- GNOME and GDM remain installed and enabled.
- Hyprland is added as an alternate session, never as the only session.
- The first test is local and reversible.
- Host integration is applied separately from Home Manager.
- Rollback removes only repository-owned links/units and leaves GNOME intact.
- Display, suspend/wake, portals, screen sharing, Electron applications, and
  CUDA/container workloads must pass before enabling another Spark.

## Fleet shape

The flake exposes one Home Manager configuration per `<user>@<host>`. The
common permanent base contains exactly `ncdu`, `lazydocker`, and `devbox`.
Logical user overlays are mapped explicitly to those identities; `armen`
currently maps to `n0b0dy@sparkle-01` and is not a default for other users.
Only genuine hardware or role differences belong in `hosts/<hostname>/`.

Selected applications and workloads pass the
[pre-install software manifest](software-manifest.md) one at a time. Rollouts
use a pilot-first sequence rather than having each host independently follow an
unpinned channel.

## Current implementation boundary

Repository-only Phase 1 now implements the exact base, stable/apps pin split,
default-deny unfree handling, desktop/shared-graphical composition, independent
Hyprland portal gate, and explicit Armen mapping. Evaluation invariants prevent
the old base, Ghostty-in-headless, implicit portals, broad unfree permission,
and VS Code from entering the reviewed profiles.

The bounded System Manager canary became exact registered/live boot-linked
generation three. The first real reboot's persistent deadline
correctly rolled generation three back; snapshot-bound verification and exact
cleanup passed. A first restoration attempt also exercised its timed rollback,
then the retry-safe second attempt restored generation three, passed two full
postflights, and automatically disarmed rollback. The guarded Tailscale handoff
then advanced the host to exact generation four. All four generations and
direct pilot roots remain, the upstream root selects generation four, the
declarative boot edge exists, both recovery surfaces are absent, and no
countdown is active. The reviewed
transactions, live pilots, disposable recovery lifecycle, real reboot
rollback, restoration, and Tailscale migration all passed. Hash-pinned helpers
deliberately contain no reboot action.

Desktop-mode root candidates exist but are inactive; personal app packages,
workload roles, and all graphical/desktop/workload activation remain
deliberately inactive. Tailscale ownership migration is complete. The first minimal Home transaction passed
disposable and real rollback, then retained exact generation one; its headless profile
emits no Home Manager user units. Its later-generation operator is also
implemented and disposable-rollback-tested, with a true no-op when Git already
matches the live generation. The separately gated pilot Nix runtime update to
2.35.2 is complete. The declarative fleet selection and read-only plan are also
implemented and host-tested. Exact Nix adoption and the complete disposable
clean-install/rollback lifecycle are host-tested. The staged guarded apply
front door converges Nix plus headless Home and now verifies the already managed
Tailscale role; it reports partial convergence because the root desktop
controller remains untouched. The active Home generation does not authorize a
raw `home-manager switch`, a systemd service
link/restart, or another root-runtime change. Host mode switching and service
changes require their own later approval.
