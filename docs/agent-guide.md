# Agent guide

[Documentation](README.md) · [AGENTS.md](../AGENTS.md) · [Prompt library](../.agents/skills/dgx-spark-ops/references/prompt-library.md)

You should be able to work on Sparkwerx without the original chat. Start with
the user's current request, not the oldest unfinished-sounding paragraph in a
pilot transcript.

## Orient quickly

1. Resolve the repository root and inspect Git status. Preserve unrelated edits.
2. Read [status](status.md) and the relevant section of [operations](operations.md).
3. Classify the task: explanation/audit, repository change, disposable test,
   or host operation. Don't silently turn one into another.
4. Use [`dgx-spark-ops`](../.agents/skills/dgx-spark-ops/SKILL.md) for fleet work,
   then follow only the references relevant to this task.
5. Compare desired state, recorded state, and live state before making a change.

Do not spend a routine session rereading every historical failed attempt.
Read the matching transaction history when you are modifying that transaction
or diagnosing an actual failure.

## Sources of truth

| Question | Source |
| --- | --- |
| What did the user choose? | [Decision register](decision-register.md) |
| What does this host select? | [fleet/hosts.json](../fleet/hosts.json) |
| What exact code/packages are pinned? | [flake.lock](../flake.lock), [packages](../packages), [bootstrap source](../bootstrap/nix/source.json), [runtime release](../root/nix/release.json) |
| What enters a profile? | [Software manifest](software-manifest.md) and evaluated `lib.dgxProfileManifests` |
| What can a command actually do? | Its implementation under [scripts](../scripts), checked against the operator guide |
| What has been proven? | Exact commit/derivation records in [docs](README.md#evidence-worth-starting-with) and [root](../root) |
| What is running now? | The correct lifecycle's status operator and sanitized host inspection |
| What's the newest upstream release? | A fresh check of the [official sources](../.agents/skills/dgx-spark-ops/references/source-map.md), not a cached version in prose |

If these disagree, report the mismatch. Don't weaken a verifier to make an old
description appear true.

## Choose the right lifecycle

| Host | Setup/application | Root status |
| --- | --- | --- |
| Newly declared Spark using generic provisioning | `dgx-setup converge` | `dgx-fleet-bootstrap status` |
| Historical `sparkle-01` on retained generation five | `dgx-setup apply`, or recognized no-op `converge` | `dgx-desktop status` and `dgx-tailscale status` |
| Any supported Home deployment | `dgx-home` first activation/update as appropriate | `dgx-home status` |

These are local-host operators, not a remote fleet scheduler.

The pilot's five generations encode its development history. New hosts use two.
The old generation-three canary classifier and `dgx-recovery restore` do not
describe or repair today's retained generation-five host.

## Route by task

- **Docs only:** check implementation, links, wording, and examples. Don't
  run activation or sudo lifecycle tests just to change prose.
- **Updates:** [update audit](../.agents/skills/dgx-spark-ops/references/update-audit.md),
  source map, and the relevant package source record. Report availability,
  ARM64/GB10 applicability, and validation separately.
- **New host:** [getting started](getting-started.md),
  [configuration limits](configuration.md#current-limits), and
  [fresh-host contract](fresh-host-convergence.md).
- **Home packages:** [user overlays](user-overlays.md) and
  [update lifecycle](2026-09-03-home-headless-update-lifecycle.md).
- **Tailscale:** [access reference](../.agents/skills/dgx-spark-ops/references/tailscale.md),
  [service runbook](../root/tailscale/README.md), and the latest host record.
- **Desktop:** [desktop contract](desktop-modes.md), the
  [Dashboard-aware tests](../root/desktop/validation/2026-09-05-dashboard-aware-stack.md),
  and [retained headless integration](../root/desktop/validation/2026-09-05-confirmed-headless-integration.md).
- **System Manager:** [root runbook](../root/system-manager/README.md), the
  matching transaction plan/result under its validation directory, and
  [frozen root dependency lane](../root/system-manager/validation/2026-09-03-root-dependency-lane.md).
- **AI workloads:** [workload map](../.agents/skills/dgx-spark-ops/references/workload-map.md),
  the selected NVIDIA playbook, and a new exact pin/storage/exposure plan.

## Lessons that change decisions

- Nix's installer, runtime, package-set inputs, and root manager have different
  update paths. “Latest Nixpkgs” does not prove “latest application,” and
  `upgrade-nix` has proposed a downgrade here.
- Hand-written package adapters exist because stock pins lagged. Verify whether
  the reason still applies; don't replace them with older stock packages.
- Registration, live activation, boot persistence, and store retention are
  distinct. A profile link alone does not prove the service is using it.
- The factory Dashboard GUI follows desktop mode; Dashboard Admin does not.
  An idle socket-activated Nix daemon is not automatically broken.
- Parse each whole `systemctl show` unit record. Property order is not stable.
- Headless Home composition does not by itself stop the host desktop.
- A rollback guard is active recovery machinery, not clutter. Detached workers
  and persistent timers can outlive the SSH connection.
- Factory Snap refreshes can produce legitimate pending reloads. Diagnose the
  exact change; don't clear flags or replay an old one-shot script blindly.
- Only the current manifest-matching test output is current evidence. Keep
  physical-host results distinct from simulated/disposable ones.

## Leave a useful handoff

Record enough for a new session to continue:

- commit/branch and any intentional dirty files;
- what changed, what did not, and the exact tests/results;
- actual host/lifecycle status, with observation time;
- any worker or rollback timer still active and its deadline;
- the next command or missing decision, with its effect;
- sanitized evidence location; never the private contents.

Do not leave an armed transition unattended just because a document or commit
is finished. For ordinary repo work, continue through verification and hand
off the result without inventing extra confirmation ceremonies.
