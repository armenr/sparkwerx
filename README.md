# DGX Spark setup

Declarative userland and fleet configuration for the DGX Spark machines, while
keeping NVIDIA DGX OS as the vendor-supported hardware-enablement layer.

## Current status

- `sparkle-01` is the pilot host.
- A sanitized baseline has been captured under `inventory/sparkle-01/`.
- Nix and the Nix daemon were already present before this repository was
  created.
- The Home Manager configuration is evaluable but has **not** been activated.
- Hyprland is represented by an opt-in module and is **disabled**.
- The accepted fleet layers, desktop modes, Armen overlay, selected software,
  exclusions, and pre-install review gate are now documented.
- The current flake/base modules are provisional and intentionally blocked from
  activation until they match those decisions.
- No host integration, GDM session link, package installation, or system
  configuration has been performed by this repository.
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
flake.nix                  Fleet entry point
flake.lock                 Pinned inputs, generated during validation
```

## Dependency updates

```bash
./scripts/update-dependencies.sh
```

The updater advances Nixpkgs and Home Manager to the current tips of their
stable 26.05 branches, verifies that the separately pinned Hyprland tag is the
latest upstream release, formats and evaluates the flake, and builds the ARM64
Home Manager, Hyprland, and portal outputs with `--no-link`. It never activates
a profile or desktop session.

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
focused audits, update plans, workload scaffolding, and narrowly authorized
pilot activation prompts.

## Safe validation

The installed Nix currently enables `nix-command` but not `flakes`, so commands
pass the feature explicitly instead of changing `/etc/nix/nix.conf`.

```bash
./scripts/check.sh
```

That evaluates the flake and Home Manager activation package. It does not run
Home Manager activation and does not modify GDM or the Ubuntu package database.

## Deliberate hold point

Do not run `home-manager switch`, install a selected application, install
Hyprland into a system profile, or add a GDM session link yet. The current
`allowUnfree` and base-module settings are known provisional conflicts listed
in the decision register. Correct and review those in a repository-only change
before any build or activation. GNOME remains the recovery desktop throughout
every graphical pilot.
