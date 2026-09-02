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
[software manifest](../../../docs/software-manifest.md). Produce one
declarative host/user role selection, the checksum-pinned Nix bootstrap or
adoption boundary, exact plan/SBOM output, guarded apply sequence, recovery
path, and postflight. Treat Tailscale as an explicit optional per-host role and
keep its mutable identity outside the Nix store. Surface unresolved role
choices, including Codex CLI ownership, instead of silently preserving manual
installs. Planning does not authorize bootstrap, installation, activation,
service migration, desktop switching, or reboot.

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
the branch matching stable Nixpkgs and keep its private wrapper aligned with the
separately reviewed current host Nix release. Treat any reappearance of stale
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
as the current full live-state authority. The inactive preflight/activation,
absent-prestate first-registration, pre-switch, and boot-persistence
snapshot/wrapper helpers are now all inapplicable; do not run them and
misclassify their expected refusal as drift. Audit the active
six-path/three-service boundary, all four profile links, the upstream root, all
three pilot roots, and the one exact boot edge directly. Keep first reboot,
rollback, deactivation, generation cleanup, pilot-root retirement, and broader
ownership behind separate plans and authorization.

Use `../../../scripts/audit-root-canary-state.sh` with the exact evaluated
generation-three candidate, the `registered-third-boot` expectation, exact
generation one as the third argument, and exact generation two as the fourth.
The expected current result is
`ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED`; any `DRIFT|...`
result is a stop condition. After a separately authorized rollback to
generation two that deliberately retains all three direct roots, use
`registered-second-triple-retained` and require
`ACTIVE_REGISTERED_GENERATION_TWO_TRIPLE_RETAINED`; that is a transition class,
not the current host state. For generation switching, registration rollback,
or later-generation work, also read the
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

The current live candidate is exact generation three, which inherits
generation two and adds only `boot-persistence-generation=3` plus the declarative
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
The current retained-state authority is the
[host attempt record](../../../root/system-manager/validation/2026-09-02-boot-persistence-host-attempt-1.md).
Its 13-subtest/two-restart disposable derivation passed with a hash-valid output
and clean host postflight. Require the manifest's boot-persistence test
`result == "passed"`, `matchesCurrent == true`, and
`hostPostflight == "clean"`; a changed transaction checksum, candidate, or test
derivation invalidates that evidence.

That PASS authorized the live-wrapper design, not the later host action. Armen
separately authorized snapshot `20260902T110421Z`; exact generation three is now
registered, selected, upstream-rooted, directly rooted, live, and boot-linked,
with generations one/two and all three direct roots retained. Require manifest
status `live-generation-three-boot-linked-retained` and current classifier
`ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED`. The snapshot is
spent. Do not rerun either live helper, recreate the activation timer, or infer
rollback/reboot/cleanup authority from the completed activation.

Live generation-three activation and the first real reboot are distinct gates.
Activation is complete, and the persistent recovery lifecycle has now passed
its exact 12-subtest/two-restart disposable test. Before touching
`scripts/root-reboot-recovery-transaction.sh`,
`scripts/audit-root-canary-state.sh`,
`root/system-manager/reboot-recovery-transaction-test.nix`, or the recovery
bundle, read the
[recovery plan](../../../root/system-manager/validation/2026-09-02-reboot-recovery-transaction-plan.md)
and exact
[test result](../../../root/system-manager/validation/2026-09-02-reboot-recovery-transaction-container-test.md).
Require manifest recovery status `isolated-lifecycle-passed-host-not-armed`,
test `result == "passed"`, `matchesCurrent == true`, and clean host postflight.

The production bundle uses a ten-minute `OnBootSec` timer, exact boot-ID guard,
confirmation `KEEP REBOOTED GENERATION THREE`, and rolled-back cleanup phrase
`CLEAN ROLLED BACK REBOOT RECOVERY`. The post-boot state class is
`ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_REBOOTED_RETAINED`; unlike the
activation-time class, it requires the reactivation-only sysinit target to be
inactive. Recovery paths are ordinary audit drift. Only the hash-pinned
recovery transaction may request the auditor's explicit
`verified-by-caller` exception after it independently verifies the complete
recovery surface.

No host recovery path is installed or armed and no real reboot occurred. The
tested transaction is not yet a live-host wrapper. Hash-pinned snapshot, arm,
post-boot confirmation, rollback-verification, and cleanup helpers remain the
next design milestone. Never run the disposable helper during an ordinary
audit, invoke the bare bundle on the host, infer arming or reboot authority from
the PASS, reuse the spent activation snapshot, or treat the live boot edge as
real-host post-reboot proof. Recovery arming and the actual reboot require two
separate explicit authorizations.

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
repository-owned fleet access service that is still awaiting migration from its
manual apt installation; it is not part of the NVIDIA factory substrate.

An audit may inspect only sanitized version, package provenance, unit state,
backend state, online state, `WantRunning`, and `RunSSH`. Never print raw
`tailscale status --json`, preferences, node addresses, node IDs, tailnet data,
auth keys, or ACL contents.

Do not restart or replace `tailscaled` over the machine's only Tailscale SSH
session. A daemon restart terminates that session. Package migration or
activation requires independently verified console/recovery access and the
rollback guard defined in the reference.

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
- Never set global `allowUnfree = true`. Permit only the exact selected package
  after it appears in the reviewed manifest.
- Keep ChatGPT, Chromium, both 1Password browser extensions, Zed, and LM Studio
  in Armen's graphical overlay. Keep Isaac and Omniverse robotics/simulation
  tooling in an independent workload role.
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
- System Manager's exact six-path/three-service canary is retained active on
  `sparkle-01` as exact generation three. Generation three is selected,
  upstream-rooted, directly pilot-rooted, and linked into `default.target` by
  the one reviewed edge. Exact generations one and two remain registered and
  directly pilot-rooted; all three roots are recovery anchors.
  Preserve its exact service/`/etc` allowlists, state/registration disclosure,
  single-boot-edge policy, Nix 2.35.2 private runtime, and closure rejection of
  Nix 2.34.8 and real `userborn`. Preserve the exact-version
  `skip-empty-tmpfiles` patch, its manifest hash/policy, and the unmanaged-rule
  regression sentinel; never allow an empty managed set to trigger global
  factory tmpfiles processing. Preserve the explicit pilot GC root: low-level
  activation is otherwise unrooted, so all exact closures and deactivation
  programs must remain retained. While active and registered, do not rerun the
  inactive-state preflight/activation, first-registration, pre-switch snapshot,
  live-switch, or boot-persistence helpers; remove a generation or root; select
  another generation; reboot; remove/change boot linkage; broaden ownership; or
  update any candidate underneath the host.
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
  `20260902T110421Z`; its host record is current authority. Preserve its exact
  six-path/three-service state, one boot edge, all three generations/roots,
  repeated postflight, and exact confirmation. That snapshot is also spent.
  The first host reboot is untested and separately gated.
- The apt-installed Tailscale package is temporary migration input. Do not
  downgrade it to the older package in locked Nixpkgs, delete its mutable
  identity, containerize the host access plane, or remove apt ownership before
  the Nix-managed service has been validated.
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
