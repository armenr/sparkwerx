# Sparkwerx documentation

[Project home](../README.md)

Start with the task you want to do. The first group is for everyday use; the
dated records are the evidence behind it.

## Human guides

| I want to… | Read |
| --- | --- |
| Set up another Spark | [Getting started](getting-started.md) |
| Choose a host's roles or understand package selection | [Configuration](configuration.md) |
| Check status, update, or recover | [Operations](operations.md) |
| See what actually works today | [Status and support](status.md) |
| Understand Nix, containers, and the factory OS | [Architecture](architecture.md) |
| Understand headless, GNOME, Hyprland, and KDE | [Desktop modes](desktop-modes.md) |
| Stream a desktop over Tailscale | [Remote desktop](remote-desktop.md) |
| Understand Armen's personal tools and mutable settings | [User overlays](user-overlays.md) |
| See the unfinished work | [Roadmap](roadmap.md) |
| Develop, open a PR, or cut a release | [Development](development.md) |

## Working with an AI agent

- [Repository instructions](../AGENTS.md): short entry point and operating rules.
- [Agent guide](agent-guide.md): source-of-truth map, task routing, and handoffs.
- [Operational skill](../.agents/skills/dgx-spark-ops/SKILL.md): fleet-specific workflow.
- [Prompt library](../.agents/skills/dgx-spark-ops/references/prompt-library.md):
  ready-to-use orientation, audit, planning, and implementation requests.
- [Official source map](../.agents/skills/dgx-spark-ops/references/source-map.md):
  upstream documentation and release breadcrumbs.

## Contracts and runbooks

- [Decision register](decision-register.md): accepted choices and explicit exclusions.
- [Software manifest](software-manifest.md): packages, closures, side effects, and readiness.
- [Fresh-host convergence](fresh-host-convergence.md): exact initial-setup lifecycle.
- [Nix bootstrap](../bootstrap/README.md) and [runtime maintenance](../root/nix/README.md):
  the installer is not the installed runtime.
- [Home updates](2026-09-03-home-headless-update-lifecycle.md).
- [Tailscale service](../root/tailscale/README.md) and
  [access-plane maintenance](../.agents/skills/dgx-spark-ops/references/tailscale.md).
- [System Manager](../root/system-manager/README.md): root integration and historical pilots.
- [Update procedure](../.agents/skills/dgx-spark-ops/references/update-audit.md).
- [AI workload map](../.agents/skills/dgx-spark-ops/references/workload-map.md).
- [Inventory privacy](../inventory/README.md).

## Evidence worth starting with

| Question | Record |
| --- | --- |
| Does the combined fresh-host workflow pass? | [2026-09-06 integration](2026-09-06-fresh-host-convergence-integration.md) |
| Did the real host reach headless safely? | [Desktop attempt 2](../root/desktop/validation/2026-09-05-host-attempt-2.md) |
| Does retained headless setup converge without changing it? | [Confirmed-headless integration](../root/desktop/validation/2026-09-05-confirmed-headless-integration.md) |
| Did Nix-owned Tailscale survive a real reboot? | [Tailscale attempt 2](../root/tailscale/validation/2026-09-05-host-attempt-2.md) |
| Was Home rollback exercised on the real host? | [Headless Home result](2026-09-03-home-headless-host.md) |
| Why are some apps packaged by hand? | [Dependency refresh](2026-09-03-dependency-refresh.md) and the per-package records linked from the manifest |
| Can Nix programs render and encode through the factory NVIDIA driver? | [Remote-desktop GPU tests](../remote-desktop/validation/2026-09-06-gpu-and-session-preparation.md) |
| Does real Hyprland virtual-display capture work on GB10? | [Capture hardware result](../remote-desktop/validation/2026-09-06-temporary-capture-host.md) |

## Reading historical records

Files named with dates describe a particular commit, candidate, and observation.
They are not live status endpoints or reusable permission to replay a command.
Older reports correctly describe earlier generations; they may not describe
the host now.

Use [status](status.md) to find the latest recorded result, then inspect the
actual machine before acting. Never copy private snapshot directories into Git
or publish their contents as documentation.
