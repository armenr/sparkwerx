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
- The exported pilot Home profile is staged as user-layer `headless`, containing
  exactly `ncdu`, `lazydocker`, and current Devbox plus Home Manager's intrinsic
  session-variable file. Factory GNOME/GDM remains running and untouched.
- GNOME, Hyprland, and Hyprland-with-portal profile graphs evaluate separately.
  Ghostty is graphical-only, and the portal has its own independent gate.
- Stable Nixpkgs remains the foundation. A separate lockfile-pinned apps input
  supplies fast-moving packages. Because both current Nixpkgs branches still
  trail Devbox, an exact upstream source/vendor-hash adapter supplies current
  Devbox 0.18.0. The apps input also exposes reviewed candidates for Zed,
  LM Studio, and Chromium without adding them to a profile.
- The `armen -> n0b0dy@sparkle-01` mapping exists, but no personal graphical
  application has been wired or installed.
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
  patched disposable Ubuntu activation/deactivation test passed: it managed only
  five allowlisted paths, skipped global tmpfiles, preserved the unmanaged
  sentinel and protected files, and rolled back inside the container. Postflight
  proved the host unchanged. Host activation and generation registration remain
  separate, forbidden gates.

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

## Dependency updates

```bash
./scripts/update-dependencies.sh
```

This is a mutating, build-authorized workflow, not the default audit command. It
preflights the exact Devbox and Hyprland release pins; advances stable Nixpkgs,
the independently scoped apps input, Home Manager, and matching System Manager
release branch; advances Tailscale only through its verified stable ARM64
artifact/checksum workflow; formats/evaluates the flake; and builds every ARM64
Home profile plus the Devbox, Tailscale, Hyprland, root canary/policy, unit,
and portal outputs with `--no-link`. It never activates a profile, service, or
desktop session, but it does rewrite pins, fetch inputs, and realize packages,
so run it only after those actions are explicitly
approved.

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

The guarded Nix 2.35.2 runtime rollout is complete. Devbox and Tailscale have
passed explicitly scoped no-link builds; that does not authorize a Home
profile, Tailscale service migration, or desktop activation. Do not run
`home-manager switch`, install Hyprland into a system profile, replace the apt
Tailscale unit, change GDM/systemd for a desktop, or activate a portal yet.
The exact System Manager container gate passed, but do not activate or register
the canary on the host. First satisfy the independent-console, collision,
snapshot, exact pilot-GC-root, and timed-rollback gates and obtain explicit
activation authorization.
GNOME remains the recovery desktop throughout every graphical pilot.
