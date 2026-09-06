---
name: dgx-spark-ops
description: Audit, plan, and safely maintain this DGX Spark fleet's Nix configuration, NVIDIA substrate boundary, Tailscale access plane, Hyprland, and AI workloads. Use for update checks, drift audits, dependency bumps, Tailscale/Tailscale SSH work, NVIDIA playbook use, workload packaging or deployment, compatibility review, and rollback planning. Do not use for generic Nix or Linux work unrelated to this fleet.
---

# DGX Spark operations

Keep DGX OS as the NVIDIA-owned hardware-enablement substrate while making the
configuration above it reproducible, reviewable, and fleet-ready.

## Start here

1. Resolve the repository root with `git rev-parse --show-toplevel`. Do not
   assume the caller's current directory is the root.
2. Read [references/operating-model.md](references/operating-model.md) and the
   repository [decision register](../../../docs/decision-register.md) before
   recommending or changing ownership boundaries, packages, profiles, desktop
   modes, user overlays, or workloads.
3. Read the [pre-install software manifest](../../../docs/software-manifest.md)
   before proposing a package realization or workload build. For System Manager
   or any root integration, also read the
   [root-manager runbook](../../../root/system-manager/README.md).
4. Select the smallest applicable mode below and read only its routed
   references.
5. Treat an unqualified request to "check", "audit", or "see what is outdated"
   as read-only. Do not turn an audit into an update.

## Modes

### Audit updates or drift

Read [references/update-audit.md](references/update-audit.md) and
[references/source-map.md](references/source-map.md). Run:

```bash
.agents/skills/dgx-spark-ops/scripts/audit-updates.sh
```

Use `--offline` only when network access is unavailable or the user requests an
offline inventory. Supplement the script with current authoritative web sources
for components it marks `MANUAL`, `UNKNOWN`, or `NOT_PINNED`.

Report availability, applicability, and validation separately. A newer version
is not automatically safe for DGX Spark.

### Plan an update

Read [references/update-audit.md](references/update-audit.md). Produce an exact
change set, source links, compatibility evidence, expected downloads/builds,
validation gates, activation boundary, and rollback procedure. Do not mutate
the host or repository merely because the user requested a plan.

### Plan software, a user overlay, or a desktop mode

Read the [decision register](../../../docs/decision-register.md),
[software manifest](../../../docs/software-manifest.md), and whichever of the
[desktop-mode](../../../docs/desktop-modes.md) or
[user-overlay](../../../docs/user-overlays.md) contracts applies.

Preserve the exact `ncdu`/`lazydocker`/current-Devbox CLI base, shared
Ghostty graphical role, exact user scope, singular desktop mode, default-deny
unfree policy, and explicit non-selections. Check current ARM64 sources and
versions, but report a package as selected-not-ready when the lock is stale.
Return the exact profile graph, closure-review plan, services/state, validation,
and rollback. Do not build, install, activate, or switch modes merely because a
design was accepted.

### Plan a fresh DGX host

Read the [architecture](../../../docs/architecture.md),
[roadmap](../../../docs/roadmap.md),
[decision register](../../../docs/decision-register.md), and
[software manifest](../../../docs/software-manifest.md). Treat
[`fleet/hosts.json`](../../../fleet/hosts.json) and
[`bootstrap/nix/source.json`](../../../bootstrap/nix/source.json) as the
declarative inputs, and run `./scripts/dgx-setup plan [HOSTNAME]` before
inventing an alternate workflow. Produce the checksum-pinned Nix bootstrap or
adoption boundary, exact plan/SBOM output, guarded apply sequence, recovery
path, and postflight. Treat Tailscale as an explicit optional per-host role and
keep its mutable identity outside the Nix store. Include the current pinned
Codex CLI in Armen's all-modes overlay when that named overlay is selected;
never put it in the fleet base or invoke its standalone installer. Planning
does not authorize bootstrap, installation, activation,
service migration, desktop switching, or reboot.

If the user explicitly requests bootstrap, use `./scripts/dgx-setup bootstrap
[HOSTNAME]`; do not invoke the vendor binary directly. An exact existing install
must resolve as a zero-mutation adoption. The clean-install branch passed its
exact disposable install, injected-failure timed-uninstall, clean retry, and
second-adoption lifecycle; read
[`docs/2026-09-03-nix-bootstrap-lifecycle.md`](../../../docs/2026-09-03-nix-bootstrap-lifecycle.md)
before using it on a declared clean ARM64 host. That PASS covers only Nix
bootstrap and grants no authority for unified apply, Tailscale, desktop,
workload, or reboot actions. Do not rerun the root-assisted lifecycle test
during an ordinary audit.

If the user explicitly requests initial convergence of a newly declared host,
read
[`docs/fresh-host-convergence.md`](../../../docs/fresh-host-convergence.md)
and use `./scripts/dgx-setup converge [HOSTNAME]`. The workflow is resumable,
never reboots, and owns exactly the guarded Nix, optional Tailscale,
factory-generation, real-reboot checkpoint, headless-generation, and generic
Home sequence. Do not replay `sparkle-01`'s historical pilot scripts or invoke
raw System Manager/Home activation. Its root-assisted combined disposable gate
passed from clean commit `cc1069cbce87974a545095b3361b78837d618437`; read
[`docs/2026-09-06-fresh-host-convergence-integration.md`](../../../docs/2026-09-06-fresh-host-convergence-integration.md).
Use it on a newly declared supported ARM64 DGX only after factory updates and
plan/SBOM review; rerun the complete gate after any functional change. When it
reports `AWAITING_REBOOT`, only a separately initiated reboot may advance it.

For retained historical `sparkle-01` configuration application, use
`./scripts/dgx-setup apply [HOSTNAME]` rather than invoking Home Manager
directly. Read
[`docs/2026-09-03-guarded-staged-apply.md`](../../../docs/2026-09-03-guarded-staged-apply.md)
as historical pre-migration evidence. The current operator composes the
independently proven Nix and headless Home transactions and verifies the
confirmed Nix-managed Tailscale and System Manager headless roles without
restarting or switching them. On exact retained `sparkle-01`, the complete
regression now returns `PLAN_STATUS=READY` and `APPLY_STATUS=COMPLETE` as a true
live-host no-op.
The historical `APPLY_STATUS=PARTIAL` result predates the separately guarded
desktop activation; do not treat it as current host truth or as authority for a
new desktop change.
The first guarded headless host attempt reached exact generation five with
Tailscale intact, then failed closed because `dgx-dashboard.service` was
correctly stopped with the GUI but incorrectly treated as a mode-independent
same-PID service. Persistent rollback and exact cleanup restored generation
four/factory GNOME without a reboot. The earlier desktop test results are
superseded. The corrected Dashboard-aware transaction, three-reboot mode,
persistent rollback, and post-Tailscale integration stack passed against exact
commit `abb852d320a01192236d862336bf60c31943714a`. A separately authorized retry
from commit `fc82217c7b85ed8ea42b2e08783dbfe2b9a05385` then retained exact
generation five in headless mode without rebooting. Read
[`docs/2026-09-05-desktop-controller-candidates.md`](../../../docs/2026-09-05-desktop-controller-candidates.md)
and the exact host result
[`root/desktop` first host-attempt record](../../../root/desktop/validation/2026-09-05-host-attempt-1.md),
the
[`Dashboard-aware validation record`](../../../root/desktop/validation/2026-09-05-dashboard-aware-stack.md)
and the
[`successful host record`](../../../root/desktop/validation/2026-09-05-host-attempt-2.md)
and the current
[`complete retained-state integration record`](../../../root/desktop/validation/2026-09-05-confirmed-headless-integration.md)
before testing or changing that role. Use only `./scripts/dgx-desktop`; never
activate a raw candidate or call `systemctl isolate` directly on the host. Do
not infer live-switch or reboot authority from the passing tests.
After changing this integration, run
`./scripts/test-post-tailscale-integration.sh` as the declared user; it keeps
the destructive-looking lifecycle entirely inside a disposable container and
requires the real apply path to remain a no-op.

### Apply an approved update

Read [references/update-audit.md](references/update-audit.md). Confirm the user
actually asked to apply the identified change. Update one ownership layer at a
time, preserve the previous pin/generation, validate before activation, and stop
at any compatibility or downgrade ambiguity.

Never combine DGX OS/driver updates, Nix runtime updates, flake updates,
container-image changes, and workload activation into one opaque operation.

### Audit, test, or change root integration

Read the [root-manager runbook](../../../root/system-manager/README.md),
[decision register](../../../docs/decision-register.md), and
[software manifest](../../../docs/software-manifest.md). Read
`../../../root/nix/README.md` as well before changing the private Nix input.

An audit may evaluate `lib.dgxRootManagerManifest`, policy assertions, lock
metadata, and dry-run plans. It must not run the root-assisted container helper,
register a profile, create state, or activate the host. Keep System Manager on
the branch matching its exact `nixpkgs-root` foundation and keep its private
wrapper aligned with the separately reviewed current host Nix release. Routine
user/package updates must exclude both System Manager and `nixpkgs-root` and
prove the full root evidence fingerprint unchanged. Read the
[root dependency lane record](../../../root/system-manager/validation/2026-09-03-root-dependency-lane.md)
before changing either root input. Treat any reappearance of stale
Nix, real `userborn`, users, wrappers, global PATH, boot links, unexpected
units, replacement ownership, global tmpfiles processing, a missing or
version-mismatched `skip-empty-tmpfiles` patch, or a processed unmanaged
tmpfiles sentinel as a stop condition.

`sudo ./scripts/test-root-canary.sh` is a separately authorized disposable
Ubuntu activation/deactivation test, not a host activation. Actual host
activation additionally requires independent local console access, exact
collision/snapshot evidence, an exact retained store output, timed rollback, and
explicit approval for the already-built output. Low-level activation does not
GC-root its closure. The live pilot therefore requires the manifest-declared
`/nix/var/nix/gcroots/dgx-setup-root-canary-pilot` symlink before rollback is
armed; do not remove it while active, substitute a floating output, or infer
permission to run `register-profile`. If root integration affects Tailscale or
desktop mode, route through those references and gates too.

The exact recorded patched derivation passed on 2026-08-24 with clean host
postflight. Require `isolatedTest.result == "passed"` and
`isolatedTest.matchesCurrent == true` in the root manifest. A changed input,
patch, or test derivation invalidates that evidence and requires a separately
authorized disposable rerun; it still never authorizes host activation.

The exact candidate's third guarded host activation attempt was retained on
2026-09-01. Read
`../../../root/system-manager/validation/2026-09-01-host-canary-attempt-3.md`
as the live-activation authority. Later that day, the separately guarded first
generation was registered and retained. Read
`../../../root/system-manager/validation/2026-09-01-first-registration-host-attempt-3.md`
as the generation-one registration authority. On 2026-09-02, the separately
authorized guarded switch retained generation two after repeated postflight and
local-console confirmation. Read
`../../../root/system-manager/validation/2026-09-02-generation-switch-host-attempt-1.md`
as the generation-two milestone authority. Later on 2026-09-02, the separately
authorized boot-persistence pilot retained generation three after repeated
postflight and local-console confirmation. Read
`../../../root/system-manager/validation/2026-09-02-boot-persistence-host-attempt-1.md`
as historical generation-three authority. The separately authorized first real
reboot later reached its persistent deadline, automatically restored exact
generation two, passed snapshot-bound rollback verification, and cleaned its
recovery surface. Read
`../../../root/system-manager/validation/2026-09-03-reboot-recovery-host-attempt-1.md`
as recovery authority. The retry-safe second restoration subsequently retained
exact generation three after two full automatic postflights. Read
`../../../root/system-manager/validation/2026-09-03-restoration-host-attempt-2.md`
as historical pre-migration authority. The later guarded Tailscale migration
retained exact generation four after a real reboot; read
`../../../root/tailscale/validation/2026-09-05-host-attempt-2.md` as inherited
access-plane authority. The corrected desktop retry then retained exact
generation five in headless mode; read
`../../../root/desktop/validation/2026-09-05-host-attempt-2.md` as transition
authority and
`../../../root/desktop/validation/2026-09-05-confirmed-headless-integration.md`
as current retained-state authority. The inactive preflight/activation,
absent-prestate first-registration, pre-switch, boot-persistence, and
restoration snapshot/wrapper helpers are now all inapplicable; do not run them
and misclassify their expected refusal as drift. Audit current root state with
`../../../scripts/dgx-tailscale status`; require
`MIGRATION_STATUS=CONFIRMED_NIX_OWNED`, exact generation five selected/live/
boot-linked in headless mode, the inherited Nix-owned unit, unchanged identity
and SSH, five registered generations and direct roots, and absent recovery,
migration, and desktop guards. Keep
another reboot, deactivation, generation cleanup, pilot-root retirement, apt
fallback removal, and broader ownership behind separate plans and
authorization.

The generation-three `audit-root-canary-state.sh ... registered-third-boot`
classifier remains historical recovery input, not the current host classifier.
For restoration, generation switching, registration rollback, or
later-generation work, also read the
[registration lifecycle plan](../../../root/system-manager/validation/2026-09-01-registration-test-plan.md).
The plan's `sudo ./scripts/test-root-registration.sh` command is a distinct
root-assisted disposable-container gate. Its exact derivation passed on
2026-09-01 with a hash-valid output and clean host postflight; read the
[registration test result](../../../root/system-manager/validation/2026-09-01-registration-container-test.md).
Require `result == "passed"` and `matchesCurrent == true` in the manifest.
Never convert that pass into permission for live registration or activation.

The separately scoped guarded first-generation transaction passed its exact
disposable failure-injection gate on 2026-09-01. Read
`../../../root/system-manager/validation/2026-09-01-first-registration-transaction-plan.md`
and the exact
[transaction test result](../../../root/system-manager/validation/2026-09-01-first-registration-transaction-container-test.md)
before touching it. Its transaction program is
`../../../scripts/root-registration-transaction.sh`; its separately authorized
disposable invocation was:

```bash
sudo ./scripts/test-root-registration-transaction.sh
```

Require the manifest's transaction-test `result == "passed"`,
`matchesCurrent == true`, and `hostPostflight == "clean"`. A changed transaction
checksum or derivation invalidates the evidence and requires a new review plus
separately authorized disposable run. Do not rerun the test during an ordinary
audit.

This container PASS granted no live authority by itself. The later live
registration separately required a clean committed tree, a fresh root-owned
snapshot no older than 30 minutes, exact `ACTIVE_RETAINED` pre-state, unchanged
protected service processes, independent console access, an armed ten-minute
registration-only rollback, and authorization bound to that snapshot. The
wrapper retained the active canary and pilot root, created no boot link,
performed no activation/deactivation or service operation, and required
exactly `KEEP REGISTRATION` before disarming rollback. Do not rerun either
`snapshot-root-registration.sh` or `register-root-canary-pilot.sh` now: the
one-time absent-registration pre-state no longer exists.

The first live wrapper invocation on 2026-09-01 failed closed during
protected-service preflight, before the rollback timer or registration
transaction. Read the
[attempt record](../../../root/system-manager/validation/2026-09-01-first-registration-host-attempt-1.md).
The cause was an order-dependent `snapshot_property` parser: in multi-unit
`systemctl show` output, properties such as `MainPID` may precede `Id`. Preserve
the corrected whole-record parser and its synthetic plus all-seven-unit
regressions; never reintroduce streaming selection that can cross a blank-line
unit boundary. The transaction checksum and all three disposable derivations
were unchanged. Snapshot `20260901T183009Z` is tied to the pre-fix commit and
retired. At that point, a corrected live attempt required a new clean commit,
fresh snapshot, independent-console verification, and new authorization bound
to that exact snapshot.

The second live attempt refused an otherwise valid snapshot at 2,207 seconds
old, before timer or mutation. Read
`../../../root/system-manager/validation/2026-09-01-first-registration-host-attempt-2.md`.
The third attempt used corrected commit `0f03d01` and fresh snapshot
`20260901T201613Z`; it armed the exact rollback, registered generation one and
the upstream extra root, passed postflight, received independent-console
confirmation plus exact `KEEP REGISTRATION`, passed repeated postflight, and
disarmed rollback before its service ran. State at that milestone was
`ACTIVE_REGISTERED_RETAINED`; the later generation-two switch supersedes it
as current authority. Preserve the historical evidence and never reuse its
spent snapshot.

The distinct disposable generation-switch transaction derivation passed all
eleven named subtests with a hash-valid output and clean host postflight. Read
both the
[2026-09-02 generation-switch plan](../../../root/system-manager/validation/2026-09-02-generation-switch-transaction-plan.md)
and the exact
[container-test result](../../../root/system-manager/validation/2026-09-02-generation-switch-transaction-container-test.md)
before touching `rootCanaryRegistrationTestGeneration`,
`scripts/root-generation-switch-transaction.sh`, or its test/helper. Its
manifest result is `passed` and must match the exact current derivation/output.
That disposable pass did not itself grant live-switch authority. Do not rerun
the one-time disposable build during an ordinary audit. The later live pilot
was separately designed, snapshot-bound, authorized, executed, and retained.
Also read the
[2026-09-02 live plan](../../../root/system-manager/validation/2026-09-02-generation-switch-live-plan.md)
and the
[retained host result](../../../root/system-manager/validation/2026-09-02-generation-switch-host-attempt-1.md)
before touching `scripts/snapshot-root-generation-switch.sh`,
`scripts/switch-root-canary-generation-pilot.sh`, or
`scripts/systemd-snapshot-property.sh`. The snapshot is spent and the
pre-switch state no longer exists. Do not rerun the snapshot or live wrapper,
invoke rollback, select or remove a generation, or remove either pilot root
without a new exact plan and authorization. Rollback keeps both pilot roots;
never remove the generation-two root as incidental cleanup.

Exact generation three inherits generation two and adds only
`boot-persistence-generation=3` plus the declarative
`default.target.wants/system-manager.target` edge. Before touching
`dgx.root.bootPersistence`, `rootCanaryBootPersistenceGeneration`,
`scripts/root-boot-persistence-transaction.sh`,
`scripts/snapshot-root-boot-persistence.sh`,
`scripts/activate-root-boot-persistence-pilot.sh`, or their tests, read the
[boot-persistence transaction plan](../../../root/system-manager/validation/2026-09-02-boot-persistence-transaction-plan.md)
and exact
[container-test result](../../../root/system-manager/validation/2026-09-02-boot-persistence-transaction-container-test.md).
Also read the
[guarded live activation plan](../../../root/system-manager/validation/2026-09-02-boot-persistence-live-plan.md).
The historical retained generation-three authority is the
[host attempt record](../../../root/system-manager/validation/2026-09-02-boot-persistence-host-attempt-1.md).
Its 13-subtest/two-restart disposable derivation passed with a hash-valid output
and clean host postflight. Require the manifest's boot-persistence test
`result == "passed"`, `matchesCurrent == true`, and
`hostPostflight == "clean"`; a changed transaction checksum, candidate, or test
derivation invalidates that evidence.

That PASS authorized the live-wrapper design, not the later host action. Armen
separately authorized snapshot `20260902T110421Z`; exact generation three was
registered, selected, upstream-rooted, directly rooted, live, and boot-linked,
with generations one/two and all three direct roots retained. That snapshot is
spent. The later real-reboot recovery attempt supersedes it as current-state
authority. Do not rerun either activation helper or recreate its timer.

Live generation-three activation and the first real reboot were distinct
gates. The persistent recovery lifecycle passed its exact
13-subtest/two-restart disposable test, including same-boot cancellation and
re-arming. Before touching
`scripts/root-reboot-recovery-transaction.sh`,
`scripts/audit-root-canary-state.sh`,
`root/system-manager/reboot-recovery-transaction-test.nix`, or the recovery
bundle, read the
[recovery plan](../../../root/system-manager/validation/2026-09-02-reboot-recovery-transaction-plan.md)
and exact
[test result](../../../root/system-manager/validation/2026-09-02-reboot-recovery-transaction-container-test.md).
Also read the
[live lifecycle plan](../../../root/system-manager/validation/2026-09-03-reboot-recovery-live-plan.md)
and the current
[first real reboot result](../../../root/system-manager/validation/2026-09-03-reboot-recovery-host-attempt-1.md)
before touching `scripts/snapshot-root-reboot-recovery.sh`,
`scripts/root-reboot-recovery-pilot.sh`, `scripts/dgx-recovery`, or
`scripts/root-recovery-restore-generation-three.sh`. Require manifest recovery
status `live-recovery-operational-host-not-armed`, live-pilot status
`repository-design-complete-host-not-armed`, test `result == "passed"`,
`matchesCurrent == true`, `subtestCount == 13`, same-boot-disarm proof, exact
helper hashes, and clean host postflight.

The production bundle uses a ten-minute `OnBootSec` timer, exact boot-ID guard,
confirmation `KEEP REBOOTED GENERATION THREE`, and rolled-back cleanup phrase
`CLEAN ROLLED BACK REBOOT RECOVERY`. The post-boot state class is
`ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_REBOOTED_RETAINED`; unlike the
activation-time class, it requires the reactivation-only sysinit target to be
inactive. Recovery paths are ordinary audit drift. Only the hash-pinned
recovery transaction may request the auditor's explicit
`verified-by-caller` exception after it independently verifies the complete
recovery surface.

The separately authorized first real reboot used snapshot
`20260902T204546Z`. Its ten-minute deadline expired before a valid confirmation,
automatic rollback restored exact generation two, snapshot-bound verification
passed, and exact cleanup removed the recovery surface. The first restoration
attempt used snapshot `20260903T042141Z`, reached healthy generation three,
then safely timed back to generation two after a typo in the old retention
phrase. Read
`../../../root/system-manager/validation/2026-09-03-restoration-host-attempt-1.md`;
that snapshot is spent historical evidence. The corrected retry used snapshot
`20260903T083058Z`, one Enter, two full automatic postflights, and automatic
rollback disarming to retain generation three without rebooting. Read
`../../../root/system-manager/validation/2026-09-03-restoration-host-attempt-2.md`.
That classifier is historical pre-migration authority: all three earlier
generations and direct roots remain recovery anchors. Generation four with
Nix-managed Tailscale, recorded in
`../../../root/tailscale/validation/2026-09-05-host-attempt-2.md`, is the
inherited access boundary. Current live authority is headless generation five,
recorded in `../../../root/desktop/validation/2026-09-05-host-attempt-2.md`;
use the generation-five-aware guarded status operators, not the generation-three
canary classifier, for current root state. No timer is armed. The historical root manifest must
retain boot status `live-generation-three-boot-linked-retained`, recorded state
`ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED`, live-attempt status
`automatic-rollback-verified-cleaned`, and restoration status
`generation-three-restored-after-verified-postflight`.

After a clean boot, `nix-daemon.service` may legitimately be inactive/dead
while the unchanged `nix-daemon.socket` is active/listening. Accept that exact
socket-activated postboot state; do not treat it as Nix failure or start the
daemon merely to satisfy an audit. Same-boot process continuity remains strict.

`scripts/dgx-recovery` is the short unprivileged operator route. It exposes
`snapshot`, `restore`, `arm`, `disarm-preboot`, `status`, `confirm`,
`verify-rolled-back`, and `cleanup-rolled-back`; neither it nor the underlying
helpers exposes a reboot action. Postboot actions invoke the exact root-owned
snapshot copy. The successful restoration path required exact rollback state,
created a private snapshot, armed a transient ten-minute generation-two
rollback, performed no reboot, and preserved all three direct roots. One Enter
authorized mutation after the local-console check; two complete automatic
postflights retained generation three and disarmed rollback. The restoration
snapshot is now spent, and `restore` should refuse the current generation-three
state. Never invoke the bare transaction, reuse a spent snapshot, remove a
root, or infer later arming/reboot authority from restoration.

The current disposable rerun initially refused a legitimate pending systemd
unit-graph reload caused by the completed factory Thunderbird Snap revision
1241 refresh. Read the
[reload disposition](../../../root/system-manager/validation/2026-09-03-thunderbird-unit-graph-reload.md).
Its one-shot helper proved all seven protected service fragments, PIDs, and
active-enter timestamps unchanged across `systemctl daemon-reload`, then ran
the current test. It is spent and intentionally refuses a clean or different
unit graph. Future `NeedDaemonReload` drift requires fresh diagnosis; do not
generalize or rerun that helper merely to clear the flag.

Keep the helper's direct `--store local` execution. Nix 2.35 does not forward
experimental-feature overrides to the daemon, while the test's `uid-range`
build requires temporary `auto-allocate-uids` and `cgroups`. Do not persist
those features or restart/reconfigure the daemon merely to run this test.
Disclose `/nix/var/nix/userpool2` and `/nix/var/nix/cgroups` as Nix
operational bookkeeping; do not delete their records casually.
Keep `NIX_USER_CONF_FILES=/dev/null` in the helper so root-specific user config
cannot add hidden settings; system `/etc/nix/nix.conf` is still read. Do not
claim this suppresses the observed non-fatal top-level Nix 2.35.2
`auto-allocate-uids` warning. The successful derivation log and valid output,
not that cosmetic warning, determine the test verdict.

### Audit, migrate, or update Tailscale

Read [references/tailscale.md](references/tailscale.md),
[references/update-audit.md](references/update-audit.md), and
[references/source-map.md](references/source-map.md). Tailscale is a
repository-owned fleet access service, not part of the NVIDIA factory
substrate. On `sparkle-01`, exact generation five inherits the Nix-owned
running service unchanged from generation four; the apt installation remains
only as inactive rollback material.

An audit may inspect only sanitized version, package provenance, unit state,
backend state, online state, `WantRunning`, and `RunSSH`. Never print raw
`tailscale status --json`, preferences, node addresses, node IDs, tailnet data,
auth keys, or ACL contents.

Do not restart or replace `tailscaled` over the machine's only Tailscale SSH
session. A daemon restart terminates that session. Package migration or
activation requires independently verified console/recovery access and the
rollback guard defined in the reference.

The exact disposable handoff, injected-failure rollback, candidate/vendor
reboots, and persistent unconfirmed-reboot rollback pass. The guarded live
migration and a fresh post-reboot Tailscale SSH reconnect also passed on
`sparkle-01`; `root/tailscale/validation/2026-09-05-host-attempt-2.md` is the
access-plane authority and the later desktop host record is current host
authority. Do not rerun `migrate` there while generation five retains that
exact Nix-owned service.
For another explicitly authorized host migration, use
`./scripts/dgx-tailscale`; do not reconstruct the low-level System Manager
commands. Run `plan` first. `migrate` requires a
clean exact commit, reruns the lifecycle test, snapshots private host evidence,
arms rollback before mutation, and launches the expected disconnect in a
detached worker. It never reboots. Require same-boot `AWAITING_REBOOT`, then a
separately authorized reboot, fresh Tailscale connection, postboot
`AWAITING_CONFIRMATION`, and `confirm`. Do not confirm on the origin boot or
remove apt ownership during this transaction.

### Add or change an AI workload

Read [references/workload-map.md](references/workload-map.md),
[references/source-map.md](references/source-map.md), the
[decision register](../../../docs/decision-register.md), and the
[software manifest](../../../docs/software-manifest.md). Start from the current
NVIDIA DGX Spark playbook, then pin every mutable source used by the resulting
configuration. Prefer Nix for tools and configuration and NVIDIA-validated
containers or source-build workflows for tightly coupled CUDA/Python runtimes.
Do not substitute a catalog-adjacent product for the workload the user selected.

## Non-negotiable invariants

- NVIDIA/DGX Dashboard owns firmware, kernel, system NVIDIA driver, CUDA base,
  Docker engine, and NVIDIA Container Toolkit.
- The permanent fleet base contains exactly `ncdu`, `lazydocker`, and
  `devbox`. Home Manager CLI/manpages and XDG/MIME/portal plumbing remain
  opt-in role concerns.
- Ghostty belongs to the shared graphical role for GNOME, Hyprland, and KDE and
  is inactive in headless mode.
- The factory `dgx-dashboard.service` GUI follows desktop mode: inactive in
  headless and active in factory GNOME. Keep the separate
  `dgx-dashboard-admin.service` active and continuity-protected in both modes;
  do not take package or unit ownership from the DGX substrate. The headless
  target must conflict explicitly with the GUI service because its factory
  `default.target.wants` edge otherwise starts it on a cold headless boot. The
  named GNOME target must non-fatally want the existing GUI service because a
  direct isolate does not traverse the factory default-target edge.
- Never set global `allowUnfree = true`. Permit only the exact selected package
  after it appears in the reviewed manifest.
- Keep ChatGPT, Chromium, both 1Password browser extensions, Zed, and LM Studio
  in Armen's graphical overlay. Keep Isaac and Omniverse robotics/simulation
  tooling in an independent workload role.
- The exact current Chromium, Zed, and LM Studio ARM64 packages are built
  candidates, not active profile members. Read
  `../../../docs/2026-09-03-chromium-package.md`,
  `../../../docs/2026-09-03-zed-package.md`, and
  `../../../docs/2026-09-03-lmstudio-package.md` before updating or wiring
  them. Chromium requires an exact root
  sandbox integration; never run it on the open web with `--no-sandbox` or
  globally relax the host user-namespace restriction. Preserve Zed's
  updater-disable wrapper and LM Studio's byte-identical Deno CLI. Treat LM
  Studio's vendor Electron `--no-sandbox` fallback under the factory AppArmor
  restriction as its own unresolved activation gate; never weaken host policy
  implicitly.
- Keep Codex CLI in Armen's all-modes overlay. Update it only through
  `scripts/update-codex.sh`, keep `check_for_update_on_startup = false`, and
  preserve mutable auth/plugin/MCP/history state plus the old standalone tree
  until the declarative launcher is activated and verified.
- The first minimal user-profile activation completed through
  `../../../scripts/dgx-home`. Read
  `../../../docs/2026-09-03-home-headless-preflight.md` and
  `../../../docs/2026-09-03-home-headless-host.md`. Real rollback and fresh
  reactivation passed; snapshot `20260903T120519Z` is current authority. The
  active headless generation contains no Home Manager user-systemd units. Do
  not raw-switch it or reuse the first-generation action for an update. Later
  generations use `../../../scripts/dgx-home update-headless`; read
  `../../../docs/2026-09-03-home-headless-update-lifecycle.md`. Its disposable
  rollback test passed. Preserve its exact live-record check, candidate roots,
  automatic timer, prior generation, partial-transition rollback, repeated
  postflight, and follow-up deployment-record reconciliation.
- Do not add or recommend VS Code, Google Chrome, NIM, NVIDIA AI Enterprise, the
  1Password desktop app, or LM Link unless Armen explicitly changes the current
  non-selection.
- Do not independently upgrade vendor-owned packages with Nix, pip, or generic
  upstream installers.
- Always dry-run `nix upgrade-nix` and compare versions. Refuse downgrades; its
  stable metadata can lag the installer-provided Nix version.
- Never run `nix flake update`, `docker pull`, `docker compose up`, package
  installation, `home-manager switch`, GDM changes, daemon restarts, or host
  updates during a read-only audit.
- Never commit secrets, model-registry tokens, cookies, private model metadata,
  or unsanitized host inventory.
- Do not use floating container tags such as `latest` or `main` as reproducible
  pins. Record the architecture-specific digest and the human-readable source
  tag.
- Keep models, caches, databases, generated media, and logs outside the Nix
  store and container image.
- Hyprland stays opt-in until the non-NixOS NVIDIA graphics bridge, portals, GDM
  entry, and rollback path are validated.
- Installing `lazydocker` never implies Docker group membership; that remains
  a reviewed root-equivalent host change.
- Installing Devbox never authorizes its installer to install, replace, or
  upgrade the repository-owned Nix runtime.
- System Manager's bounded six-path/three-service generation-three canary is
  the historical foundation for the current host. Exact generation four
  inherits that boundary and adds only the reviewed Nix-managed Tailscale
  service and links. Exact generation five inherits that access plane and adds
  only the reviewed desktop-mode marker and three thin target links. Generation
  five is selected, upstream-rooted, directly pilot-rooted, live in headless
  mode, and linked at boot; generations one through four and their roots remain
  rollback anchors. Recovery is absent.
  Preserve the exact service/`/etc` allowlists, state/registration disclosure,
  one declarative boot edge, Nix 2.35.2 private runtime, and closure rejection
  of Nix 2.34.8 and real `userborn`. Preserve the exact-version
  `skip-empty-tmpfiles` patch, its manifest hash/policy, and the unmanaged-rule
  regression sentinel; never allow an empty managed set to trigger global
  factory tmpfiles processing. Preserve the explicit pilot GC root: low-level
  activation is otherwise unrooted, so all exact closures and deactivation
  programs must remain retained. While active and registered, do not rerun the
  inactive-state preflight/activation, first-registration, pre-switch snapshot,
  live-switch, boot-persistence, or restoration helpers; remove a generation or root;
  reboot; manually add/remove boot linkage; broaden ownership; or update any
  candidate underneath the host. The old generation-three and generation-four
  classifiers are historical after the desktop switch; use the guarded
  generation-five-aware status paths for the current root-level exact state.
  Preserve exact passed-test evidence only while it matches the evaluated
  derivation. Preserve the two failed-closed live-attempt records and never
  reuse their commit/time-bound snapshots. The third guarded attempt registered
  and retained exact generation one without changing live activation, services,
  or boot linkage. Preserve its full-state record as historical registration
  authority. A build or container test never implies host registration or
  activation.
- The generation-two live pilot completed from snapshot
  `20260902T083437Z`; its host record is historical authority. Preserve its
  exact helper hashes, whole-record systemd parser regression, 30-minute private
  snapshot gate, protected `FragmentPath`/`MainPID`/active-enter continuity,
  ten-minute rollback-before-switch ordering, exact `KEEP GENERATION TWO`
  confirmation, repeated postflight, and no-boot/no-broader-ownership boundary.
  The spent snapshot grants no authority for a rerun, rollback, cleanup, or
  reboot. The later generation-three pilot completed from snapshot
  `20260902T110421Z`; its host record is historical authority and its snapshot
  is spent. Persistent recovery then ran from snapshot `20260902T204546Z` on
  the separately authorized first real reboot. Its deadline expired,
  automatic rollback restored generation two, and verification/cleanup passed.
  Restoration attempt one then safely timed back; retry-safe attempt two used
  snapshot `20260903T083058Z`, passed two full postflights, and automatically
  retained generation three without rebooting. That successful restoration
  record is the recovery authority immediately preceding Tailscale migration.
  Preserve generations one through three and their direct roots as rollback
  anchors, plus the boot edge, absent recovery, and Nix socket-idle lesson.
- The Tailscale access-plane authority is snapshot `20260905T084503Z` and
  `root/tailscale/validation/2026-09-05-host-attempt-2.md`. Current host
  authority is desktop snapshot `20260905T153316Z` and
  `root/desktop/validation/2026-09-05-host-attempt-2.md`, followed by the
  complete retained-state result in
  `root/desktop/validation/2026-09-05-confirmed-headless-integration.md`.
  Preserve exact
  generation five, all selected/upstream/pilot roots, the inherited Nix-managed
  `tailscaled.service`, mutable node identity, `RunSSH=true`, multi-user boot
  edge, headless dispatcher, and absent migration/desktop guards.
- The apt-installed Tailscale package is retained fallback input. Do not
  downgrade it to the older package in locked Nixpkgs, delete its mutable
  identity, containerize the host access plane, or treat the installed apt
  files as live ownership. Package/repository removal is a separate reviewed
  cleanup after an observation period.
- Preserve the exact `scripts/dgx-tailscale` operator, its private snapshot,
  generation-three/vendor rollback roots, persistent timer, original boot-ID
  gate, and clean commit/helper hashes throughout an in-flight migration.
- Keep `tailscaled.service` available from `multi-user.target`; headless mode
  must not disable the fleet access plane.

## Evidence and output

For an audit, return a compact table with:

- component and ownership layer;
- installed or pinned version/revision/digest;
- latest candidate and authoritative source;
- status: `CURRENT`, `UPDATE_AVAILABLE`, `AHEAD`, `HOLD`, `MANUAL`,
  `NOT_PINNED`, or `UNKNOWN`;
- compatibility evidence and recommended next action.

State the audit date, network limitations, commands that were not run, and
whether anything changed. Cite current web claims next to the claim they
support.

For reusable invocation examples, read
[references/prompt-library.md](references/prompt-library.md).
