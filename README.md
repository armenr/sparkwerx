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
  supplies current Devbox and exposes reviewed current candidates for Zed,
  LM Studio, and Chromium without adding them to a profile.
- The `armen -> n0b0dy@sparkle-01` mapping exists, but no personal graphical
  application has been wired or installed.
- No Phase 1 package output was built or fetched, and no host integration, GDM
  session link, package installation, service change, or system configuration
  was performed.
- Tailscale `1.102.3` and Tailscale SSH are currently working from a manual
  official apt installation. That installation is migration input; this
  repository has not yet replaced or restarted it.

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
before auditing, packaging, migrating, restarting, or updating Tailscale.

## Repository layout

```text
.agents/skills/             Repository-local Codex operational skills
bootstrap/                 Reviewed host-level integration (currently empty)
docs/                      Architecture and rollout decisions
hosts/                     Per-host Home Manager configuration
inventory/                 Sanitized, non-secret baseline records
modules/home/              Reusable user-level modules
scripts/                   Inventory, validation, and dependency-update helpers
flake.nix                  Fleet entry point and evaluation invariants
flake.lock                 Exact stable/apps/Home Manager/Hyprland input pins
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

The human-reviewed size and package findings are in the
[software manifest](docs/software-manifest.md).

## Dependency updates

```bash
./scripts/update-dependencies.sh
```

This is a mutating, build-authorized workflow, not the default audit command. It
advances stable Nixpkgs, the independently scoped apps input, and Home Manager;
verifies that the separately pinned Hyprland tag is still the latest upstream
release; formats/evaluates the flake; and builds every ARM64 Home profile,
Hyprland, and portal output with `--no-link`. It never activates a profile or
desktop session, but it does rewrite `flake.lock`, fetch inputs, and realize
packages, so run it only after those actions are explicitly approved.

Hyprland release tags are bumped deliberately rather than automatically because
each new compositor release must pass the NVIDIA/ARM64 build gate first.

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

Phase 1 stops before realization. Do not remove `--dry-run`, run the dependency
updater, run `home-manager switch`, install a selected application, install
Hyprland into a system profile, change GDM/systemd, or activate a portal yet.
First review the measured closure costs—especially Ghostty and the portal—and
grant the next build scope explicitly. GNOME remains the recovery desktop
throughout every graphical pilot.
