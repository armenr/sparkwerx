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
  `aarch64-linux`; no Home Manager configuration has been activated.
- The exported pilot Home profile is staged as user-layer `headless`: its exact
  fleet base is `ncdu`, `lazydocker`, and current Devbox, with Armen's current
  Codex CLI layered above it plus Home Manager's intrinsic session-variable
  file. It emits no Home Manager user-systemd unit, including the otherwise
  generic `tray.target`. Factory GNOME/GDM remains running and untouched.
- GNOME, Hyprland, and Hyprland-with-portal profile graphs evaluate separately.
  Ghostty is graphical-only, and the portal has its own independent gate.
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
  ARM64 bundle and owns its future launcher plus permissive defaults. The
  package is built but not activated; the visible standalone 0.152.0 launcher
  remains migration input. Exact evidence is in the
  [Codex package record](docs/2026-09-03-codex-cli-package.md).
- Devbox 0.18.0 and the official Tailscale 1.102.3 ARM64 package plus inert
  systemd-unit tree were built with `--no-link` and SBOM-reviewed. They were not
  installed into a profile or activated.
- Tailscale `1.102.3` and Tailscale SSH are currently working from a manual
  official apt installation. The repository now pins the same current stable
  release and declares the future unit, but has not replaced or restarted the
  live apt daemon.
- Nix 2.35.2 is active in the machine-wide default profile and the restarted
  daemon after a checksum/cache-verified ARM64 rollout. The installer artifact
  remains at its expected provisioning version, 2.35.1. The default
  `upgrade-nix` fallback still targets stale 2.34.8 and remains blocked.
- System Manager 1.1.0 is an exact, matching-branch root-manager candidate. Its
  109-path / 230.0 MiB ARM64 canary contains the exact-version
  `skip-empty-tmpfiles` safety patch and anti-downgrade policy. The exact
  activation, registration-lifecycle, first-registration, generation-switch,
  boot-persistence, and persistent first-reboot recovery container tests passed.
  The first separately authorized real reboot exercised that recovery: the
  ten-minute deadline expired, exact no-boot generation two was restored, the
  rollback passed verification, and its recovery surface was cleaned. The
  retry-safe no-reboot restoration then returned generation three to exact
  registered/live/boot-linked state, passed two complete postflights, and
  automatically disarmed its rollback. Current classifier result is
  `ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED`; all three numbered
  generations and direct pilot roots remain, the upstream root selects
  generation three, the one declarative boot edge exists, and no recovery is
  armed. No broader root role exists. The postboot Nix gate recognizes a
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
| Per-machine differences | `hosts/<hostname>/` |
| Secrets | External secret store; never committed here |

Start with the [decision register](docs/decision-register.md), then review the
[pre-install software manifest](docs/software-manifest.md),
[desktop-mode contract](docs/desktop-modes.md), and
[user-overlay contract](docs/user-overlays.md). See
[docs/architecture.md](docs/architecture.md) for the ownership boundary,
[docs/roadmap.md](docs/roadmap.md) for sequencing, and the
[Tailscale operations reference](.agents/skills/dgx-spark-ops/references/tailscale.md)
before auditing, packaging, migrating, restarting, or updating Tailscale. Read
[the Nix runtime diagnosis](root/nix/README.md) before running `upgrade-nix`,
and the [root-manager runbook](root/system-manager/README.md) before evaluating,
testing, registering, or activating System Manager.

## Repository layout

```text
.agents/skills/             Repository-local Codex operational skills
bootstrap/                 Reviewed host-level integration and activation hold
docs/                      Architecture and rollout decisions
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

The first headless Home activation has one short, guarded interface:

```bash
./scripts/dgx-home status
./scripts/dgx-home preflight
./scripts/dgx-home activate-headless
```

The activation command snapshots the exact prior user state, arms a ten-minute
automatic rollback, applies only the four-package headless profile, verifies
it, and disarms rollback automatically. It has no confirmation phrase, sudo,
reboot, root role, desktop switch, or Tailscale change. See the
[first-activation preflight](docs/2026-09-03-home-headless-preflight.md).

## Dependency updates

```bash
./scripts/update-dependencies.sh
```

This is a mutating, build-authorized workflow, not the default audit command. It
preflights the exact Devbox and Hyprland release pins; advances stable Nixpkgs,
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
approved.

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

The guarded Nix 2.35.2 runtime rollout is complete. Devbox, Tailscale, and the
three selected graphical application candidates have passed explicitly scoped
no-link builds; that does not authorize a Home profile, Chromium sandbox role,
Tailscale service migration, or desktop activation. Do not run
`home-manager switch`; use only the guarded `scripts/dgx-home` transaction for
the first profile. Do not install Hyprland into a system profile, replace the apt
Tailscale unit, change GDM/systemd for a desktop, or activate a portal yet.
System Manager is currently exact registered/live/boot-linked generation three
after the first real reboot's verified automatic rollback, the first
restoration attempt's safe timed rollback, and the retry's two verified
postflights plus automatic retention. All three numbered generations and
direct pilot roots remain recovery anchors, the recovery surface is clean, and
no timer is armed. Do not rerun spent activation, registration,
generation-switch, boot-persistence, recovery, or restoration helpers; remove
a profile generation/root; or reboot without the current plan. Later recovery
arming and reboot remain distinct gates, and the helpers expose no reboot
action.
GNOME remains the recovery desktop throughout every graphical pilot.
