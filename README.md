# DGX Spark setup

Declarative userland and fleet configuration for the DGX Spark machines, while
keeping NVIDIA DGX OS as the vendor-supported hardware-enablement layer.

## Current status

- `sparkle-01` is the pilot host.
- The accepted pristine baseline is committed, with a sanitized inventory under
  `inventory/sparkle-01/`.
- Nix and the Nix daemon were already present before this repository was
  created.
- Repository-only Phase 1 policy alignment is complete and evaluates on
  `aarch64-linux`; the first guarded Home activation and real rollback test now
  pass on the pilot.
- The exported pilot Home profile is active as user-layer `headless`: its exact
  fleet base is `ncdu`, `lazydocker`, and current Devbox, with Armen's current
  Codex CLI layered above it plus Home Manager's intrinsic session-variable
  file. It emits no Home Manager user-systemd unit, including the otherwise
  generic `tray.target`. Factory GNOME/GDM remains installed and is
  intentionally inactive in confirmed headless mode.
- GNOME, Hyprland, and Hyprland-with-portal profile graphs evaluate separately.
  Ghostty is graphical-only, and the portal has its own independent gate.
- Thin root controllers for `headless` and factory `gnome` are implemented
  without taking ownership of desktop packages or GDM. After one safe rollback
  exposed the factory Dashboard boundary, the corrected guarded retry retained
  exact generation five in headless mode with Nix-managed Tailscale intact.
  The complete transaction, mode, rollback, Tailscale, plan, and apply suite
  now passes against that live retained state. See the
  [current integration record](root/desktop/validation/2026-09-05-confirmed-headless-integration.md).
- Stable Nixpkgs remains the user/fleet foundation. The live System Manager
  evidence has its own immutable root Nixpkgs lane, while a separate
  lockfile-pinned apps input supplies fast-moving packages. The 2026-09-03
  guarded refresh advanced both user/package lanes to their current branch
  heads, built every profile without activation, and proved the root lane
  byte-for-byte unchanged. Because both current Nixpkgs branches still
  trail Devbox, an exact upstream source/vendor-hash adapter supplies current
  Devbox 0.18.0. The apps input supplies current Chromium and stock comparison
  packages; exact official ARM64 adapters now supply current Zed 1.18.0 and LM
  Studio 0.4.23-1. All three remain outside every Home profile.
- The `armen -> n0b0dy@sparkle-01` mapping exists, but no personal graphical
  application has been wired or installed. Chromium, Zed, and LM Studio have
  passed their package/closure gates; their real graphical gates remain open.
  Chromium needs an exact root sandbox role, and LM Studio retains an explicit
  vendor Electron sandbox caveat.
- Armen's all-modes overlay now contains the current Codex CLI 0.153.0 official
  ARM64 bundle and owns its active launcher plus permissive defaults. The
  package and high-precedence launcher are active; the old standalone 0.152.0
  release tree remains only as rollback input. Exact evidence is in the
  [Codex package record](docs/2026-09-03-codex-cli-package.md).
- Devbox 0.18.0 is active in the Home profile. The repository's official
  stable ARM64 Tailscale 1.102.3 package and System Manager unit now own the
  live daemon and preserve Tailscale SSH plus the existing mutable identity.
- The Tailscale handoff survived its deliberate SSH disconnect, a fresh
  reconnect, one guarded real reboot, and another fresh Tailscale SSH
  connection before confirmation. Exact System Manager generation five now
  inherits that Nix-owned access plane while selected/live/boot-linked in
  headless mode; all migration and desktop guards are absent. The apt
  package/repository remain installed only as inactive fallback material; see
  the [retained host record](root/tailscale/validation/2026-09-05-host-attempt-2.md).
- Nix 2.35.2 is active in the machine-wide default profile and the restarted
  daemon after a checksum/cache-verified ARM64 rollout. The installer artifact
  remains at its expected provisioning version, 2.35.1. The default
  `upgrade-nix` fallback still targets stale 2.34.8 and remains blocked.
- `fleet/hosts.json` is now the machine-readable selection surface for the
  pilot: exact base, Armen mapping/overlay, headless user composition, optional
  Tailscale, and selected-but-inactive workloads. `scripts/dgx-setup plan`
  validates it, verifies the exact installed bootstrap artifact, evaluates the
  selected Home candidate when Nix is available, and reports every remaining
  apply gate without changing profiles or services. `scripts/dgx-setup
  bootstrap` now adopts an exact healthy install as a verified no-op; its clean
  fresh-host branch uses the pinned official plan, an automatic rollback, the
  exact current runtime, and factory/GPU/access continuity checks. The adoption
  branch is host-tested, and the exact disposable clean-install, injected
  failure/rollback, clean retry, and second-adoption lifecycle passed. The
  Nix-only bootstrap is ready for declared clean ARM64 hosts through that one
  operator. `scripts/dgx-setup apply` composes the proven Nix and headless Home
  transactions and verifies retained Nix-managed Tailscale plus the System
  Manager headless role without restarting or switching them. Exact
  `sparkle-01` now returns `PLAN_STATUS=READY` and `APPLY_STATUS=COMPLETE` as a
  true no-op. A separate resumable `scripts/dgx-setup converge` candidate now
  composes the pristine-host Nix, optional Tailscale, factory/reboot, headless,
  and generic Home stages without replaying the pilot history or performing a
  reboot. Its combined root-assisted disposable gate remains required before
  another DGX may use it.
- System Manager 1.1.0 is an exact, matching-branch root-manager candidate. Its
  109-path / 230.0 MiB ARM64 canary contains the exact-version
  `skip-empty-tmpfiles` safety patch and anti-downgrade policy. The exact
  activation, registration-lifecycle, first-registration, generation-switch,
  boot-persistence, and persistent first-reboot recovery container tests passed.
  The first separately authorized real reboot exercised that recovery: the
  ten-minute deadline expired, exact no-boot generation two was restored, the
  rollback passed verification, and its recovery surface was cleaned. The
  retry-safe no-reboot restoration then returned generation three before the
  guarded Tailscale migration advanced the host to generation four and the
  guarded desktop transition advanced it to generation five. Generation five
  is selected, upstream-rooted, directly pilot-rooted, live, boot-linked, and
  headless; all five numbered generations and direct pilot roots remain, and
  no recovery, migration, or desktop rollback is armed. The postboot Nix gate recognizes a
  cleanly idle daemon behind its active socket, and `scripts/dgx-recovery`
  provides short commands without a reboot action.

## Operating model

| Layer | Owner |
| --- | --- |
| Firmware, kernel, NVIDIA driver, CUDA base, DGX OS | NVIDIA/DGX Dashboard |
| Nix daemon bootstrap and small host integration | Reviewed bootstrap in this repository |
| Tailscale package, service, SSH desired state, and headless enablement | Nix plus reviewed root configuration after migration |
| Exact fleet CLI base (`ncdu`, `lazydocker`, `devbox`) and approved user configuration | Nix flake and Home Manager |
| Switchable headless/GNOME/Hyprland/KDE mode plus shared Ghostty terminal in graphical modes | Nix plus Home Manager and reviewed root integration |
| Armen-only graphical applications and browser extensions | Named `armen` Home Manager overlay |
| AI/robotics services and their mutable data | Independent workload roles plus external persistent storage |
| Per-machine selections | `fleet/hosts.json`, composed by `hosts/<hostname>/` |
| Secrets | External secret store; never committed here |

Start with the [decision register](docs/decision-register.md), then review the
[pre-install software manifest](docs/software-manifest.md),
[desktop-mode contract](docs/desktop-modes.md), and
[user-overlay contract](docs/user-overlays.md). See
[docs/architecture.md](docs/architecture.md) for the ownership boundary,
[docs/roadmap.md](docs/roadmap.md) for sequencing, and the
[fresh-host convergence contract](docs/fresh-host-convergence.md) for the
resumable clone-to-headless candidate. Read the
[Tailscale operations reference](.agents/skills/dgx-spark-ops/references/tailscale.md)
before auditing, packaging, migrating, restarting, or updating Tailscale. Read
[the Nix runtime diagnosis](root/nix/README.md) before running `upgrade-nix`,
and the [root-manager runbook](root/system-manager/README.md) before evaluating,
testing, registering, or activating System Manager.

## Repository layout

```text
.agents/skills/             Repository-local Codex operational skills
bootstrap/                 Plain-JSON Nix bootstrap pin, plan, and apply hold
docs/                      Architecture and rollout decisions
fleet/                     Declarative per-host role and user selections
hosts/                     Per-host Home and inert root-manager configuration
inventory/                 Sanitized, non-secret baseline records
modules/home/              Reusable user-level modules
modules/system/            Narrow non-NixOS root-manager modules
packages/                  Exact current-release adapters and source hashes
patches/                   Narrow, version-guarded upstream safety patches
root/                      Reviewed Nix, Tailscale, and System Manager runbooks
scripts/                   Inventory, validation, and dependency-update helpers
flake.nix                  Fleet entry point and evaluation invariants
flake.lock                 Exact stable/apps/Home/desktop/root-manager pins
```

## Read-only manifest and validation

The installed Nix currently enables `nix-command` but not `flakes`, so commands
pass the feature explicitly instead of changing `/etc/nix/nix.conf`.

The fresh-host front door starts with the read-only plan:

```bash
./scripts/dgx-setup plan
```

It reads the plain-JSON host and bootstrap declarations before requiring Nix.
On a host with Nix, evaluation may fetch missing locked flake sources, but it
does not build/install packages, mutate a profile, change a service, enroll
Tailscale, switch the desktop, or reboot. On the pilot it also verifies the
exact live generation-five headless controller and its inherited Nix-managed
Tailscale role.

The corresponding bootstrap-only operator is:

```bash
./scripts/dgx-setup bootstrap
```

On `sparkle-01` this is a tested, zero-mutation adoption check. On a truly clean
host it is implemented to verify the latest pin, generate and validate the
official install plan, arm a 15-minute receipt-driven uninstall timer, install
Nix with persistent flakes, advance to the separately pinned runtime, and
verify systemd/GPU/existing-service/Tailscale continuity before automatically
disarming. Its exact disposable-host lifecycle passed; read the
[validation record](docs/2026-09-03-nix-bootstrap-lifecycle.md) before using it
on another declared clean ARM64 Spark. This is a Nix-only bootstrap, not
authorization for unified apply or any optional role.

The candidate clone-to-headless operator is:

```bash
./scripts/dgx-setup converge <hostname>
```

It is the one command to rerun after an expected graphical/Tailscale
disconnect and after the separately initiated first reboot. It never reboots.
It advances only when the exact previous phase verifies, and both root phases
start with persistent rollback. A normal new host is composed directly from
`fleet/hosts.json` through generic Home and System Manager modules. This lane
is not deployment-approved until its combined gate is recorded as passed; see
the [fresh-host convergence contract](docs/fresh-host-convergence.md).

The guarded staged apply operator is:

```bash
./scripts/dgx-setup apply
```

It first prints the complete plan, then runs the exact install-or-adopt Nix
transaction and the exact headless Home first-activation or update transaction.
On the current pilot it verifies confirmed Nix-managed Tailscale and the
generation-five headless controller without restarting or switching either
one, and ends with `APPLY_STATUS=COMPLETE` as a true no-op. The
[original guarded staged apply record](docs/2026-09-03-guarded-staged-apply.md)
and its `PARTIAL` result are historical pre-migration evidence.

After changing the fleet/apply/Tailscale integration, run the single combined
regression as the declared user:

```bash
./scripts/test-post-tailscale-integration.sh
```

It checks the read-only plan, reruns the clean-host Nix bootstrap and full
Tailscale ownership/reboot/rollback lifecycles only inside disposable
containers, and proves the live staged apply is an exact no-op for Nix, Home,
System Manager, Tailscale, protected services, and mutable Codex state. The
complete current sequence passed on the retained pilot; see the
[post-Tailscale integration record](docs/2026-09-05-post-tailscale-integration.md).

```bash
./scripts/check.sh
```

This evaluates every profile and the policy invariants with `flake check
--no-build`. It does not realize a package, run Home Manager activation, or
modify GDM, systemd, services, or the Ubuntu package database.

The machine-readable direct/effective package manifest is:

```bash
nix --extra-experimental-features "nix-command flakes" \
  eval --json .#lib.dgxProfileManifests.aarch64-linux
```

The separately scoped root-manager manifest is:

```bash
nix --extra-experimental-features "nix-command flakes" \
  eval --json .#lib.dgxRootManagerManifest.aarch64-linux
```

The human-reviewed size and package findings are in the
[software manifest](docs/software-manifest.md).

## Minimal Home profile

The first headless Home activation has one short, guarded interface. On the
already activated pilot, use `status`; `preflight` and `activate-headless` are
deliberately first-generation-only commands for a pristine fleet host:

```bash
./scripts/dgx-home status
./scripts/dgx-home preflight
./scripts/dgx-home activate-headless
./scripts/dgx-home update-headless
```

The activation command snapshots the exact prior user state, arms a ten-minute
automatic rollback, applies only the four-package headless profile, verifies
it, and disarms rollback automatically. It has no confirmation phrase, sudo,
reboot, root role, desktop switch, or Tailscale change. See the
[first-activation preflight](docs/2026-09-03-home-headless-preflight.md) and
[successful pilot result](docs/2026-09-03-home-headless-host.md).

Later dependency commits use `update-headless`. It is a no-op when the live
generation already matches Git; otherwise it snapshots the exact current
generation, retains the next candidate, arms rollback before mutation, keeps
the prior generation, and disarms automatically after two postflights. See the
[generation-update lifecycle](docs/2026-09-03-home-headless-update-lifecycle.md).

## Dependency updates

```bash
./scripts/update-dependencies.sh
```

This is a mutating, build-authorized workflow, not the default audit command. It
verifies/advances the official checksum-pinned ARM64 `nix-installer` bootstrap
artifact without executing it; preflights the exact Devbox and Hyprland release
pins; advances stable Nixpkgs,
the independently scoped apps input, and Home Manager; advances Tailscale only
through its verified stable ARM64 artifact/checksum workflow; advances Codex
only through OpenAI's stable ARM64 bundle/checksum workflow; advances Zed and
LM Studio only through their exact official ARM64 artifact workflows;
formats/evaluates the flake; and builds every ARM64 Home profile plus Chromium,
Codex, Devbox, Zed, LM Studio, Tailscale, Hyprland, root canary/policy, unit,
and portal outputs with
`--no-link`. The
live System Manager and its exact `nixpkgs-root` foundation are a separately
reviewed frozen lane. The updater fingerprints that complete lane before and
after the user/package refresh and stops if anything moved. It never activates
a profile, service, or desktop session, but it does rewrite pins, fetch inputs,
and realize packages, so run it only after those actions are explicitly
approved. The standalone bootstrap-pin check is
`./scripts/update-nix-installer.sh --check`.

The latest completed run is recorded in the
[2026-09-03 dependency-refresh evidence](docs/2026-09-03-dependency-refresh.md).

Hyprland release tags are bumped deliberately rather than automatically because
each new compositor release must pass the NVIDIA/ARM64 build gate first.

System Manager's exact current disposable activation/deactivation derivation
passed. The helper remains outside the automated update workflow:
`sudo ./scripts/test-root-canary.sh`. Any input, patch, or test change makes
the recorded pass stale and requires a separately authorized rerun.

## Codex operations skill

The repository-local `$dgx-spark-ops` skill captures the ownership boundaries,
source breadcrumbs, workload packaging decisions, update procedure, and lessons
from the pilot. Codex discovers it automatically while working anywhere in this
repository.

Armen's overlay declares the current Nix-managed Codex CLI and maximally
permissive approval/permission defaults for every desktop mode. Its tested
reconciler changes only those keys plus the centrally managed self-update
switch in `~/.codex/config.toml`; it leaves auth, plugins, MCP servers, project
trust, desktop preferences, and history mutable.

For a safe first pass:

```text
$dgx-spark-ops Audit sparkle-01 for updates and drift. Be read-only; separate
availability, DGX applicability, and validation, and make no changes.
```

The deterministic local/remote inventory pass can also be run directly:

```bash
.agents/skills/dgx-spark-ops/scripts/audit-updates.sh
```

See the
[prompt library](.agents/skills/dgx-spark-ops/references/prompt-library.md) for
focused audits, profile-SBOM reviews, update plans, workload scaffolding, and
narrowly authorized pilot activation prompts.

## Deliberate hold point

The guarded Nix 2.35.2 runtime, first headless Home rollout, and Nix-managed
Tailscale migration are complete. The three selected graphical application
candidates have passed their scoped build gates. That does not authorize a
Chromium sandbox role or desktop activation. Do not run a raw
`home-manager switch`; use `scripts/dgx-home update-headless` for reviewed
later-generation changes. Do not install Hyprland into a system profile,
manually replace the Nix-managed Tailscale unit, change GDM/systemd for a
desktop, or activate a portal yet.
System Manager is currently exact registered/live/boot-linked generation four.
All four numbered generations and direct pilot roots remain recovery anchors;
the recovery and migration-guard surfaces are clean, and no timer is armed. Do
not rerun spent activation, registration,
generation-switch, boot-persistence, recovery, or restoration helpers; remove
a profile generation/root; or reboot without the current plan. Later recovery
arming and reboot remain distinct gates, and the helpers expose no reboot
action.
GNOME remains the recovery desktop throughout every graphical pilot.
The first live headless attempt is cleanly rolled back. Do not retry it until
`scripts/test-desktop-stack-integration.sh` passes and its exact evidence is
recorded; use only `scripts/dgx-desktop` for the later guarded retry.
