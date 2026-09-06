![Sparkwerx — Factory core. Your stack. Repeatable.](docs/assets/sparkwerx.svg)

<p align="center">
  <a href="docs/getting-started.md">Get started</a> ·
  <a href="docs/configuration.md">Configure</a> ·
  <a href="docs/operations.md">Operate</a> ·
  <a href="docs/status.md">What's ready</a> ·
  <a href="docs/agent-guide.md">For AI agents</a>
</p>

Sparkwerx turns a factory NVIDIA DGX Spark into a repeatable development and AI
machine—without replacing DGX OS with NixOS or taking over NVIDIA's GPU stack.

The idea is simple: **get a Spark, clone the repo, declare its role, and make
the configuration repeatable.** Nix handles packages and configuration;
Home Manager handles the user environment; System Manager handles specific
host services. CUDA-heavy workloads can use pinned containers or source builds
where those fit the vendor-supported path.

## Why this exists

One carefully configured machine is useful. Being able to recreate it—and
bring up the next three without rediscovering every decision—is better.

- **Keep the factory core.** NVIDIA retains the OS, driver, CUDA, Docker,
  Container Toolkit, and Dashboard packages.
- **Know what you're installing.** Explicit package selections, exact pins,
  and a practical [software manifest](docs/software-manifest.md).
- **Make access a choice.** Optional Nix-managed Tailscale, with node identity
  and account state kept outside Git and the Nix store.
- **Keep headless genuinely useful.** Stop GDM and the Dashboard GUI while
  preserving remote access, compute services, and the installed factory desktop.
- **Keep personal tools personal.** Armen's overlay is separate from the
  three-tool fleet base.
- **Have a way back.** Test transitions in disposable environments, retain
  previous generations, and arm rollback before host changes.

## What's ready

Recorded project status: **2026-09-06**. These are tested capabilities, not a
claim that every future host or upstream release has been validated.

| Capability | Today |
| --- | --- |
| Fresh-host Nix → services → headless → Home setup | Implemented; combined disposable lifecycle and pilot no-op integration passed |
| Fleet CLI base | `ncdu`, `lazydocker`, `devbox` |
| Armen's all-modes tools | Nix-managed Codex CLI and explicitly chosen high-trust defaults |
| Tailscale + Tailscale SSH | Optional per host; live migration and real reboot verified on the pilot |
| Headless host mode | Confirmed on `sparkle-01`; factory GNOME remains installed |
| General desktop switching | Not finished; current switch operator is pilot-specific |
| Ghostty and Hyprland | Built candidates/profile work; graphical host rollout remains open |
| Chromium, Zed, LM Studio | Packages built and reviewed; not activated in Home profiles |
| KDE and AI/robotics workloads | Planned, not deployed |

The [status page](docs/status.md) separates live results, container tests,
built candidates, and planned work. The [roadmap](docs/roadmap.md) tracks the
remaining work. There is no general-purpose package picker or fleet-wide
unattended updater yet.

## Get started

The repository is private: authenticate to GitHub before cloning. Keep the
checkout name below; the project is Sparkwerx, but existing commands and
recovery paths still use `DGX-setup` / `dgx-setup`.

**New checkout only:**

```bash
mkdir -p ~/Development
git clone https://github.com/armenr/sparkwerx.git ~/Development/DGX-setup
cd ~/Development/DGX-setup
```

Before installing anything, follow the [getting-started guide](docs/getting-started.md)
to check prerequisites, add your host to
[`fleet/hosts.json`](fleet/hosts.json), and commit its declaration.

**Inspect the plan; no profiles or services are changed:**

```bash
./scripts/dgx-setup plan
```

**After reviewing the plan and installation scope:**

```bash
./scripts/dgx-setup converge
```

Run as the declared user, not with `sudo`; the operator asks for elevated access
where needed. It is resumable, but it is an **install/apply command**, not a
status check. Rerun it after the expected disconnects. It never reboots:
when it reports `AWAITING_REBOOT`, you perform the separate reboot and
reconnect before the displayed rollback deadline.

The current complete workflow targets **headless ARM64 Sparks with one
explicit Armen user mapping and the tested Home package set**. Review the
[configuration limits](docs/configuration.md#current-limits) before copying a
declaration.

## Understand the pieces

| Piece | Job |
| --- | --- |
| [Factory DGX OS](docs/architecture.md#ownership) | Hardware support and NVIDIA-managed infrastructure |
| [Nix](root/nix/README.md) | Exact package versions, builds, and development environments |
| [Home Manager](docs/user-overlays.md) | User packages, launchers, and selected non-secret settings |
| [System Manager](root/system-manager/README.md) | Reviewed service and desktop-target configuration on Ubuntu |
| [Workload roles](.agents/skills/dgx-spark-ops/references/workload-map.md) | Future application runtimes, with explicit storage and exposure |
| [Git](docs/configuration.md) | Host choices, package pins, decisions, and sanitized evidence |

Nix does not make containers mandatory, and containers do not replace Nix.
See the [architecture guide](docs/architecture.md#nix-or-containers) for how we
choose between them.

## Useful front doors

```bash
# Read-only host/configuration comparison
./scripts/dgx-setup plan

# Read-only user-profile status
./scripts/dgx-home status

# Read-only release/drift audit; --offline skips remote lookups
.agents/skills/dgx-spark-ops/scripts/audit-updates.sh --offline
```

For updates, recovery, access checks, and command effects, use the
[operations guide](docs/operations.md). Don't use an old pilot transcript as
an installation recipe.

## For AI agents

Start with [AGENTS.md](AGENTS.md), then the
[agent guide](docs/agent-guide.md). The repository includes the
[`dgx-spark-ops` skill](.agents/skills/dgx-spark-ops/SKILL.md) and a
[copyable prompt library](.agents/skills/dgx-spark-ops/references/prompt-library.md).

A useful first request:

```text
$dgx-spark-ops Orient yourself in Sparkwerx. Compare the current repository
and host with the latest recorded evidence. Explain what's active, what's
only a candidate, and the next useful step. Make no changes.
```

An agent should not need the original conversation to work here. It should
also never mistake an old test pass for permission to change the host.

## Find your way around

[Documentation index](docs/README.md) ·
[Architecture](docs/architecture.md) ·
[Decisions](docs/decision-register.md) ·
[Software manifest](docs/software-manifest.md) ·
[Validation evidence](docs/2026-09-06-fresh-host-convergence-integration.md)

Changes should explain their scope, preserve rollback, and pass the appropriate
checks. See [validation and documentation maintenance](docs/operations.md#validation).
