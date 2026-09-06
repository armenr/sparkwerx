# Operate Sparkwerx

[Documentation](README.md) · [Getting started](getting-started.md) · [Status](status.md)

Run commands from `~/Development/DGX-setup` as the declared user unless a
specific test says otherwise. The root operators request sudo themselves.
A successful plan is information, not permission to apply it.

## Status checks

**All supported hosts:**

```bash
./scripts/dgx-setup plan
./scripts/dgx-home status
```

**Generic fresh-host lifecycle:**

```bash
./scripts/dgx-fleet-bootstrap status
```

**Historical pilot `sparkle-01`:**

```bash
./scripts/dgx-desktop status
./scripts/dgx-tailscale status
```

These inspect state; root status can require sudo to inspect private recovery
records. They do not intentionally change the host. Nix evaluation may fetch
missing locked sources.

The recorded healthy pilot results are `DESKTOP_STATUS=HEADLESS_CONFIRMED`
and `MIGRATION_STATUS=CONFIRMED_NIX_OWNED`. A generic completed host reports
`FLEET_BOOTSTRAP_STATUS=HEADLESS_CONFIRMED`. If a guard is active, use the
reported transition state instead of assuming the recorded checkpoint applies.

## Know what changes

| Command | Effect |
| --- | --- |
| `dgx-setup plan [HOSTNAME]` | Read-only plan; another hostname gives declaration-only information |
| `dgx-setup bootstrap [HOSTNAME]` | Installs Nix on an eligible clean host or adopts an exact existing install |
| `dgx-setup converge [HOSTNAME]` | Resumes initial setup, including root transitions and Home activation |
| `dgx-setup apply [HOSTNAME]` | Applies supported Nix/Home changes and verifies retained pilot root roles |
| `dgx-home update-headless` | Updates a reviewed Home generation; no-op if already exact |
| `dgx-desktop headless` | Pilot-specific initial factory-to-headless transaction |
| `dgx-tailscale migrate` | Historical-pilot access migration; not a generic fresh-host installer |
| `update-dependencies.sh` | Rewrites user/package pins and builds candidates; does not activate them |

No current operator is a generic “switch to any desktop” or “update every
running service” command. Don't invoke migration/initial-switch commands on
already confirmed state. See [desktop modes](desktop-modes.md) and the
[fresh-host contract](fresh-host-convergence.md).

## Updates

Start with an audit:

```bash
.agents/skills/dgx-spark-ops/scripts/audit-updates.sh
```

Or use `--offline` for local inventory without remote lookups. Offline findings
cannot establish the newest release.

The individual artifact checks are:

```bash
./scripts/update-nix-installer.sh --check
./scripts/update-tailscale.sh --check
./scripts/update-codex.sh --check
./scripts/update-zed.sh --check
./scripts/update-lmstudio.sh --check
```

Checks may fetch metadata or artifacts into temporary storage; they do not
rewrite pins or activate profiles. Nix installer checking also verifies the
artifact's reported version. Review each candidate's source and compatibility.

After approving the repository update/build scope, the combined updater is:

```bash
./scripts/update-dependencies.sh
```

This can download and build substantial closures. It keeps the proven root
lane separate, fingerprints it before/after, and does not activate user or
host state. Nix runtime, System Manager, root-service updates, and workload
activation are separate procedures.

Review the diff and tests, commit the intended changes, then use the
[Home update operator](2026-09-03-home-headless-update-lifecycle.md) for an
approved user-profile update. Record successful deployment before another
update. Never substitute a raw `home-manager switch`, a blanket
`nix flake update`, or an unchecked `nix upgrade-nix`.

Details: [update runbook](../.agents/skills/dgx-spark-ops/references/update-audit.md)
and [Nix runtime runbook](../root/nix/README.md).

## Recovery and troubleshooting

First inspect the operator that owns the in-flight phase.

| Symptom | What to do |
| --- | --- |
| SSH disconnected during access migration | Reconnect; the detached worker continues. Check status and the rollback deadline. |
| Graphical terminal disappeared during headless transition | Expected when GDM stops. Use Tailscale SSH or the independent console. |
| Guard path already exists | Check status. It may represent active work or a completed rollback awaiting cleanup. |
| `ROLLED_BACK_CLEANUP_PENDING` | Diagnose the failure, then use that operator's `cleanup-rolled-back`; don't delete state manually. |
| Snapshot is too old | No new mutation should be inferred. Use the current workflow to obtain a fresh snapshot after rechecking state. |
| `NeedDaemonReload=yes` | Identify the changed unit graph. A factory Snap refresh can cause it; no blanket reload/restart workaround. |
| Nix daemon inactive after boot | Check the exact socket state. An active/listening socket can be healthy. |
| `auto-allocate-uids` warning | Use the command's exit status and test output as the verdict. Don't persist experimental flags just to hide it. |
| A verifier expects generation four but sees five | Check whether you invoked a historical helper. Don't roll the machine backward to satisfy an old check. |
| `xterm-ghostty` is unknown over SSH | Terminal capability data is missing on the remote side. Track a terminfo fix; don't install the entire graphical role just for `clear`. |

`rollback` and `cleanup-rolled-back` act only on the matching transaction.
In particular, `dgx-desktop rollback` is **not** a permanent “return to GNOME”
command after a confirmed switch has removed its guard.

Never remove a pilot root, generation, apt fallback, or timer as housekeeping.
Never use an old snapshot merely because its path still exists.

## Validation

Choose checks that match the change:

| Change | Checks |
| --- | --- |
| Documentation | `python3 scripts/check-docs.py`, `git diff --check` |
| Skill instructions | Docs checks plus the skill-creator validator, when available |
| Nix configuration/policy | `./scripts/check.sh` (`flake check --no-build`) |
| Home rollback mechanics | `./scripts/test-dgx-home-rollback.sh`, `./scripts/test-dgx-home-update-rollback.sh` |
| Fresh-host workflow | `./scripts/test-fresh-host-convergence-integration.sh` |
| Desktop integration | `./scripts/test-desktop-stack-integration.sh` |
| Access/application integration | `./scripts/test-post-tailscale-integration.sh` |

Evaluation can fetch locked sources but does not build packages. The lifecycle
suites do build/run tests and may need sudo. They use disposable containers
or temporary homes for mutations and check the live pilot through inspection
or exact no-op routes. They are not routine health probes.

For a functional fresh-host change, the complete integration gate must pass
from a clean committed tree and have its exact result recorded. Do not claim
it passed merely because evaluation or a cached older derivation succeeded.

Documentation checks validate local links, local Markdown anchors, examples,
and wording. They do not verify external URLs or execute installation examples.

## Maintain the docs

Keep the README short enough to understand the project without reading the
pilot log. Update [status](status.md) when a real milestone changes readiness;
link the dated evidence rather than copying its whole transcript.

When documenting a command, say whether it inspects, downloads/builds, or
changes the host. Check its actual interface. Keep future work clearly marked
and use exact package versions only with a date/source. Preserve secrets and
private snapshots outside published documentation.
