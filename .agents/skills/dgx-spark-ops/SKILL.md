---
name: dgx-spark-ops
description: Audit, configure, and maintain the Sparkwerx DGX Spark fleet through its Nix, access, desktop, and workload workflows. Use for this fleet's update checks, drift, host setup, package changes, Tailscale SSH, root integration, and recovery. Not for unrelated generic Linux or Nix work.
---

# Sparkwerx operations

Preserve NVIDIA DGX OS while making the selected software above it reproducible.
The skill routes work; it is not a deployment authorization or a list of
historical commands to replay.

## Start with the current task

1. Resolve the repository root and read [AGENTS.md](../../../AGENTS.md).
2. Read the [status page](../../../docs/status.md). Treat it as dated evidence,
   then inspect the actual host when the task requires current state.
3. Select the task below. Read only its required references; historical root
   plans are for matching root changes, not every routine session.
4. Keep audit, repository build, host activation, and reboot separate. Continue
   already approved work without redundant approval ceremonies; stop at actual
   missing authority, failed checks, or decisions.
5. Before changing ownership, packages, profiles, or workloads, read the
   [operating model](references/operating-model.md),
   [decisions](../../../docs/decision-register.md), and
   [software manifest](../../../docs/software-manifest.md).

## Task routing

| Task | Required references and route |
| --- | --- |
| Orientation or handoff | [Agent guide](../../../docs/agent-guide.md), [operations](../../../docs/operations.md); inspect without changing anything |
| Update/drift audit | [Update audit](references/update-audit.md), [source map](references/source-map.md); use `scripts/audit-updates.sh` from this skill |
| Update plan | Update audit plus the relevant package/role evidence; no edits or builds merely to produce a plan |
| Approved user/package update | Update audit, software manifest, source record, [Home update lifecycle](../../../docs/2026-09-03-home-headless-update-lifecycle.md) |
| New host | [Configuration](../../../docs/configuration.md), [fresh-host contract](../../../docs/fresh-host-convergence.md), [passed integration](../../../docs/2026-09-06-fresh-host-convergence-integration.md); plan before `dgx-setup converge` |
| Nix-only bootstrap/runtime | [Bootstrap](../../../bootstrap/README.md), [runtime runbook](../../../root/nix/README.md); keep installer and runtime updates distinct |
| Tailscale | [Access reference](references/tailscale.md), update audit, [service runbook](../../../root/tailscale/README.md), and latest host evidence |
| Desktop/graphical apps | [Desktop modes](../../../docs/desktop-modes.md), [user overlays](../../../docs/user-overlays.md), package records, and [current desktop evidence](../../../root/desktop/validation/2026-09-05-confirmed-headless-integration.md) |
| Root manager or transaction | [Root runbook](../../../root/system-manager/README.md), [root dependency lane](../../../root/system-manager/validation/2026-09-03-root-dependency-lane.md), and that transaction's plan/test/host records |
| AI workload | [Workload map](references/workload-map.md), source map, decisions, and software manifest; use the selected Spark playbook, then pin its inputs |

Read the matching files completely before acting on their instructions.

## Audit contract

An unqualified “check,” “audit,” or “what's outdated?” is read-only. Public
metadata lookups, source browsing, evaluation, and dry runs are allowed;
pin rewrites, package installation, image pulls, enrollment, service operations,
root tests, and activation are not implied.

From the repository root:

```bash
.agents/skills/dgx-spark-ops/scripts/audit-updates.sh
```

Use `--offline` when requested or networking is unavailable. Mark remote
findings unknown, not current. Follow up `MANUAL`, `UNKNOWN`, and
`NOT_PINNED` results with the relevant authoritative sources during an online audit.

Report installed/pinned state, newest candidate, applicability, and validation
separately. A moving branch isn't proof that an application is current.
The Nixpkgs fallback target isn't proof of the newest Nix release.

## Apply contract

Use the existing operator for the actual host/lifecycle. A normal new node uses
`dgx-setup converge`, not the pilot's canary sequence. The generic path uses
two root generations and a separate first reboot; the historical pilot has five.

- Plan and review the exact package/service/state effects.
- Preserve the previous pin/generation and the required retention roots.
- Require current matching tests before the corresponding host change.
- Use the operator's snapshot, rollback-before-mutation, detached worker, and
  confirmation/postflight behavior. Do not replace it with raw activation.
- Check status after reconnecting; timers can continue after a disconnect.
- Do not reboot unless the current task explicitly authorizes it.
- Do not remove fallback packages, roots, or state as incidental cleanup.

`dgx-setup apply` and `converge` are not inspection commands just because
they are no-ops when everything matches.

## Fleet-specific rules that must survive changes

- Factory DGX OS, driver, CUDA, Docker, Toolkit, and packages stay NVIDIA-owned.
  Never install a competing system GPU stack.
- Exact base: ncdu, lazydocker, Devbox. Ghostty is graphical-only. Armen's
  personal tools stay separate; no globally permissive unfree package setting.
- Respect the recorded software exclusions. A catalog neighbor is not a
  substitute for the workload the user selected.
- Tailscale stays native and available in headless mode. Preserve its identity,
  SSH setting, and apt fallback; never print raw preferences/status, node IDs,
  addresses, auth keys, or tailnet policy.
- Nix owns the pilot's running Tailscale. Don't rerun its completed migration.
- Headless stops factory GDM and Dashboard GUI; Dashboard Admin stays active.
  Keep the explicit target dependencies that handle both reboot and direct
  mode transitions.
- Nix's idle service can be healthy behind its exact active socket. Preserve
  whole-record systemd parsing and diagnose real reload drift.
- System Manager retains the exact empty-tmpfiles patch and sentinel, private
  Nix 2.35.2, and rejection of stale Nix, real userborn, users, wrappers,
  global PATH/packages, and unapproved ownership.
- Preserve root test wrappers' local-store execution, temporary experimental
  flags, and user-config isolation. The known UID warning alone isn't failure.
- Chromium's sandbox, Zed's updater/Vulkan checks, and LM Studio's Electron
  fallback/Deno integrity are separate graphical gates. Don't weaken AppArmor.
- Pin OCI architecture-specific digests and source/build inputs. Keep models,
  caches, databases, media, credentials, and other mutable state external.
- Test on ARM64 and pilot before additional hosts. A container reboot test
  is not evidence of a physical-host reboot.

## Evidence and handoff

Name the exact commit/candidate and tests run, distinguish new results from
older evidence, and state what changed and what did not. If a transition is
in flight, include its status, deadline, recovery route, and required next step.

Use the [prompt library](references/prompt-library.md) for concise requests.
Use the [agent guide](../../../docs/agent-guide.md) for the source-of-truth map
and historical-record routing.
