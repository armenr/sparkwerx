# System Manager root canary

This directory documents the bounded non-NixOS root-manager pilot for the
existing Ubuntu-based DGX OS substrate. The configuration is defined by
`hosts/sparkle-01/system.nix` and `modules/system/minimal-root.nix`.

Nothing in this directory, the flake input, or a successful build activates the
manager. On 2026-08-24, two separately authorized live canaries activated and
then rolled back on their timed guards: attempt 1 followed a verifier false
positive, while attempt 2 passed corrected automatic postflight but did not
receive the exact human retention confirmation. On 2026-09-01, attempt 3 passed
the full guarded flow and was retained after independent local-console
confirmation. That original activation owned exactly five paths and three
services.
Later that day, the guarded first-generation registration attempt passed and
was retained after its own independent local-console confirmation. On
2026-09-02, the separately guarded generation switch retained, registered,
selected, and activated exact generation two after repeated postflight and
local-console confirmation. Later that day, the separately authorized
boot-persistence pilot retained, registered, selected, and activated exact
generation three plus its one declarative boot edge. The separately authorized
first real reboot then exercised persistent recovery. Its ten-minute deadline
expired, automatic rollback restored exact registered/live no-boot generation
two, and snapshot-bound verification plus exact cleanup passed. Generations
one and two remain registered, all three pilot roots remain, generation three
is available for guarded restoration, and no broader root role exists.

## Reviewed candidate

| Field | Reviewed value |
| --- | --- |
| Manager | System Manager 1.1.0, MIT |
| Source | `numtide/system-manager` `release-26.05` |
| Revision | `05e08c6dd739d7f3204e71322594bb8095334cfb` |
| Source timestamp | 2026-08-14 14:22:29 UTC |
| Platform | `aarch64-linux` |
| Private Nix runtime | Official Nix 2.35.2 release flake at `2c73b59da29606068c0c98db015dd3a66955525d` |
| Local safety patch | `skip-empty-tmpfiles`, SHA-256 `32756de30fd5730ebe60cce6ef89fc924ccd4eb3530e21ceb53fdf6073ba0e9a` |
| Built canary closure | 109 paths, 230.0 MiB NAR |
| Activation/deactivation container test | **PASS** for the exact recorded derivation |
| Registration lifecycle container test | **PASS** for the exact recorded derivation; test made no host change |
| Guarded first-registration transaction test | **PASS** for exact failure-injection derivation |
| Guarded generation-switch transaction test | **PASS** for exact failure-injection derivation |
| Guarded boot-persistence transaction test | **PASS** for exact 13-subtest/two-restart derivation; test made no host change |
| Persistent first-reboot recovery | **PASS** for exact 13-subtest/two-restart lifecycle and first real reboot; missed deadline automatically restored generation two, verification/cleanup passed, host recovery is unarmed |
| Host registration | Exact generations one and two registered; generation two selected/upstream-rooted; generation three directly retained for restoration |
| Host activation | Exact generation-two canary active with no boot edge after verified automatic rollback |
| Rollback anchors | All three exact direct pilot roots remain; generation two is the reviewed no-boot rollback state |

The release branch deliberately matches stable Nixpkgs/Home Manager 26.05.
System Manager is a candidate for small reviewed root integration above DGX OS;
it is not allowed to turn the machine into NixOS or own NVIDIA components.

## Host canary attempt 1

The exact candidate activated on `sparkle-01` at `2026-08-24T06:25:55Z` with
the retained output and ten-minute rollback timer in place. Its version-1 state
contained only the five reviewed paths and three service keys, and all protected
service, system, GPU, and sanitized Tailscale checks passed.

The first live helper then compared the canary link with its wrapper directory
instead of the immutable payload nested below that wrapper. It failed closed
and left rollback armed. Exact deactivation ran at `06:35:55Z`, exited 0, and
removed the complete canary surface. Postflight found the exact empty version-0
state, no registration, unchanged protected-file hashes, zero failed units, and
all factory/access services healthy.

The rollback journal also exposed an upstream duplicate stop request for
`system-manager.target`: the saved service map already contains the target and
System Manager 1.1.0 appends it again. The first stop succeeds; the duplicate
logs a non-fatal “unit not loaded” error which upstream intentionally does not
propagate. The warning and exact pinned-source disposition are retained in the
[host attempt record](validation/2026-08-24-host-canary-attempt-1.md).

The resolved-payload verifier was corrected before attempt 2 and passed against
the live host.

## Host canary attempt 2 and reboot confirmation

The corrected helper activated the same exact candidate at
`2026-08-24T07:07:28Z`. Its automatic postflight passed the resolved five-path,
three-service boundary, protected-file hashes, factory/access services, system,
GPU, and sanitized Tailscale checks. The prompt then received an accidental
empty line instead of exactly `KEEP CANARY`, so it failed closed and left the
ten-minute timer armed. An immediate rerun correctly refused the already-active
canary collision. Timed exact deactivation ran at `07:17:29Z` and completed
successfully.

The [attempt 2 record](validation/2026-08-24-host-canary-attempt-2.md) preserves
the exact timeline, passed checks, known duplicate-stop warning, and completed
post-rollback protected-file hash check. The later
[post-reboot audit](validation/2026-09-01-post-reboot-audit.md) confirmed all
managed and forbidden paths absent, exact empty version-0 state, no
registration, the candidate still directly retained, zero failed units, and
healthy Nix, Tailscale/Tailscale SSH, desktop, Docker, DGX, NVIDIA, and GPU
state. It also records a later factory Firefox Snap refresh that temporarily set
`NeedDaemonReload=yes`. Armen acknowledged the generated unit graph with a
daemon reload; no protected service restarted, and full preflight passed again.

## Host canary attempt 3 retained

An initial 2026-09-01 activation invocation safely refused a snapshot that was
13 seconds beyond the 30-minute limit and changed nothing. With a new exact
snapshot and new authorization, the helper activated the canary at
`2026-09-01T10:37:44Z`. Automatic postflight passed, Armen verified the
physical console and entered exactly `KEEP CANARY`, repeated postflight passed,
and systemd stopped the rollback timer at `10:37:51Z` before its service ran.

Independent inspection confirmed version-1 state with exactly the five managed
paths and three service keys, the expected services/targets active, every
forbidden and registration path absent, the pilot root intact, zero failed
units, healthy protected services/GPU/Tailscale SSH, and no pending daemon
reload. The [attempt 3 record](validation/2026-09-01-host-canary-attempt-3.md)
remains the authority for that original live activation. The later
[first-registration attempt 3 record](validation/2026-09-01-first-registration-host-attempt-3.md)
is the authority for the first registered-generation milestone. The
[retained generation-two host record](validation/2026-09-02-generation-switch-host-attempt-1.md)
is the generation-two milestone authority. The
[retained generation-three host record](validation/2026-09-02-boot-persistence-host-attempt-1.md)
is the current full live-state authority.

Do not rerun the inactive-state preflight or activation helper while this
canary remains active. Do not rerun the first-registration helper now that its
required absent pre-state no longer exists. Do not rerun the generation-switch
or boot-persistence snapshot/live helpers against the retained post-state. Do
not remove any retention root or generation, rewrite the selected generation,
remove the boot edge, reboot, or broaden the role without a new reviewed plan
and explicit authorization.

## Exact canary ownership

The base evaluated configuration has no global packages and declares only:

- `/etc/dgx-setup/canary`, a repository-identifying symlink that refuses to
  replace a collision;
- `/etc/systemd/system`, containing only the three units below;
- `dgx-setup-canary.service`, a no-network oneshot that tests the canary link;
- `system-manager.target`, started explicitly by the activation engine;
- `sysinit-reactivation.target`, System Manager activation infrastructure; and
- `system-manager.target.wants/dgx-setup-canary.service`, the generated dependency
  symlink for the canary unit.

It declares no port, socket, secret, user, group, setuid wrapper, application
state, desktop change, Tailscale unit, Nix daemon unit, Docker unit, or GDM unit.
Generations one and two are not linked into the factory default target.
Generation three preserves that ownership and adds only the sixth tracked path,
`default.target.wants/system-manager.target -> ../system-manager.target`.

System Manager itself writes operational rollback bookkeeping at
`/var/lib/system-manager/state/system-manager-state.json` during low-level
activation. Deactivation removes managed links/units and empties that state,
but deliberately leaves the empty state file. That exact residual path is part
of the SBOM; it is not application data.

The canary build and original isolated activation test do not register a
generation. Registration has two logical outputs:

- the Nix profile at
  `/nix/var/nix/profiles/system-manager-profiles/system-manager`; and
- the additional direct root at
  `/nix/var/nix/gcroots/system-manager-current`.

The profile also materializes its parent directory and numbered
`system-manager-N-link` history. Treat that expanded profile surface as part of
the registration SBOM; the two logical paths are not literally the only
filesystem objects created.

Those paths were absent until separately authorized live registration. On
2026-09-01, the guarded transaction retained exactly `system-manager` ->
`system-manager-1-link` -> the exact candidate plus a direct
`system-manager-current` root to the same candidate. That was the exact state
at the first-registration milestone. The later guarded switch added exact
`system-manager-2-link`, selected generation two, and moved the upstream root
to generation two while retaining generation one and both direct pilot roots.
The guarded boot-persistence pilot then added exact `system-manager-3-link`,
selected and upstream-rooted generation three, and preserved all earlier links
and all three direct pilot roots. No fourth or unknown registered generation
exists. The current exact surface and operating rules are in the
[retained generation-three host record](validation/2026-09-02-boot-persistence-host-attempt-1.md).

Low-level activation does not create either registration path and does not
otherwise GC-root its store output. A live pilot must therefore retain the exact
reviewed closure with the manifest-declared direct root
`/nix/var/nix/gcroots/dgx-setup-root-canary-pilot` before its rollback timer is
armed. This root is a deliberately temporary pilot mechanism, not a substitute
for upstream generation registration. It must remain until deactivation is
verified; removing it while active can strand `/etc` links, unit programs, and
the rollback executable after a Nix garbage collection.

## Generation-registration lifecycle: test passed

Source inspection of pinned System Manager 1.1.0 found four behaviors that the
fleet wrapper must not hide:

1. `register-profile` runs `nix-env --set` first and creates the extra GC
   root second. A root collision can therefore make the command fail after the
   profile has already advanced.
2. Replacing `system-manager-current` is remove-then-create, not an atomic
   symlink rename.
3. The actual profile is the full path ending in `system-manager`. Selecting a
   numbered profile generation does not activate it and does not update the
   separate `system-manager-current` root.
4. Deactivation removes managed files/services but does not unregister the
   profile, delete generation history, or remove the extra root. Upstream 1.1.0
   does not implement automatic rollback on activation failure.

The repository now defines a separate two-generation disposable test for those
semantics. Its current derivation is
`/nix/store/m4zm42h6f8dch5mfm6aq6cpjp9jwzk90-container-test-dgx-root-canary-registration.drv`.
The design and exact assertions are recorded in the
[registration test plan](validation/2026-09-01-registration-test-plan.md).

The exact derivation **passed** on 2026-09-01. Nix realized the expected,
hash-valid output only after all nine subtests completed. Independent host
postflight found the canary still `ACTIVE_RETAINED`, both host registration
paths absent, all protected services healthy with no pending reload, systemd
running with zero failed units, a healthy GPU, and healthy sanitized Tailscale
SSH state. The exact evidence is in the
[registration container-test record](validation/2026-09-01-registration-container-test.md).

The reviewed helper remains:

```bash
sudo ./scripts/test-root-registration.sh
```

It registers and switches generations only inside the disposable Ubuntu
container and requires the same exact safe host-state class before and after.
Do not rerun it during an ordinary audit. Any changed lifecycle derivation
invalidates this pass and requires new review plus separate authorization. This
pass authorizes design of the live registration/rollback transaction only; it
does not authorize host registration, activation, boot linkage, or removal of
the pilot root.

## Guarded first-generation transaction: live registration retained

The reviewed design wraps the exact upstream helper with a strict
first-generation transaction. Its mutation program is
`scripts/root-registration-transaction.sh`, SHA-256
`86c4be22ed350782920905897d80616b3949998d2662fd04ab9d1f5c3f4078a9`.
It starts only from an absent dedicated profile directory and absent upstream
extra root, requires the exact pilot retention root, verifies the exact two-link
generation-one profile plus direct extra root, and removes only exact
transaction-owned artifacts on failure. It never activates/deactivates the
manager, changes boot linkage, reloads systemd, restarts a service, or removes
the pilot root. Unknown profile entries and foreign collisions fail closed and
are not deleted.

The distinct disposable failure-injection derivation
`/nix/store/lxnykcyvjn18pdv7y9rr1ryhvjgicazg-container-test-dgx-root-canary-registration-transaction.drv`
**passed** on 2026-09-01. Its hash-valid output is
`/nix/store/mrslm372127pgwbfv3r7kprj2igxpki2-container-test-dgx-root-canary-registration-transaction`,
with hash
`sha256:1smdvp76zf0hz5cxzjjghf8c2z4hjkvbkwf4ikmgpf2cz8fv4ram`.
All nine preflight, partial-failure, fail-closed, success, idempotent rollback,
and cleanup subtests completed. The prior lifecycle and activation derivations
remain unchanged.

Independent host postflight found the canary still `ACTIVE_RETAINED`, both
registration surfaces absent, all protected services active with no pending
reload, systemd running with zero failed units, a healthy GPU, and healthy
sanitized Tailscale SSH state. See the
[transaction plan](validation/2026-09-01-first-registration-transaction-plan.md)
and exact
[container-test evidence](validation/2026-09-01-first-registration-transaction-container-test.md).

The reviewed invocation was:

```bash
sudo ./scripts/test-root-registration-transaction.sh
```

Do not rerun it during an ordinary audit. Any transaction or derivation change
invalidates this evidence and requires new review plus separate authorization.
This PASS did not itself authorize the private snapshot or live wrapper. The
later live attempt separately required a clean committed tree, a fresh
root-owned registration snapshot, independent console access, an exact
ten-minute registration-only rollback, and new authorization bound to that
snapshot. The reviewed helpers are
`scripts/snapshot-root-registration.sh` and
`scripts/register-root-canary-pilot.sh`. The live wrapper creates no boot link
and performs no activation; it retains registration only after repeated
postflight and the exact `KEEP REGISTRATION` confirmation.

The first live wrapper invocation on 2026-09-01 **failed closed before
mutation**. Its snapshot passed, then a wrapper parser incorrectly associated
the next unit's `MainPID` with `nix-daemon.service` because `systemctl show`
emitted `MainPID` before `Id`. The failure occurred before the rollback timer,
`registration_started=true`, or `apply-first`. Independent postflight found the
canary still `ACTIVE_RETAINED`, every registration path absent, and both
transient rollback units absent. The parser now consumes complete
blank-line-delimited unit records and has passed synthetic plus all-seven-unit
regression checks. The transaction checksum and all three disposable
derivations are unchanged. Read the
[attempt record](validation/2026-09-01-first-registration-host-attempt-1.md).
That old snapshot is retired.

Attempt 2 then refused snapshot `20260901T193734Z` because it was 2,207
seconds old, 407 seconds beyond the hard limit. The refusal again occurred
before timer or mutation, and postflight was clean. See the
[attempt 2 record](validation/2026-09-01-first-registration-host-attempt-2.md).

Attempt 3 used corrected commit `0f03d01` and fresh snapshot
`20260901T201613Z`. The snapshot and complete preflight passed, the exact
registration-only rollback timer was armed, generation one and the extra root
were created, and automatic postflight passed. Armen verified the physical
console and entered exactly `KEEP REGISTRATION`; repeated postflight passed and
the timer was disarmed before its service ran. Independent postflight classified
the host `ACTIVE_REGISTERED_RETAINED` with exact registration links, unchanged
activation, healthy protected services/GPU/Tailscale SSH, no boot link, and no
broader ownership. See the
[retained attempt 3 record](validation/2026-09-01-first-registration-host-attempt-3.md).

Do not run the registration helper again while this state is retained. A
rollback, second generation, generation switch, reboot/boot milestone, or real
managed service requires a separate plan and authorization.

## Guarded generation switch: generation two retained live

This repository milestone defines a marker-only generation two plus
`scripts/root-generation-switch-transaction.sh`. Generation two inherits the
same empty package set, five-path/three-service boundary, disabled root-manager
defaults, and absent boot edge as generation one; it changes only the harmless
`registration-test-generation=2` canary line.

The transaction requires exact registered/live generation one and two separate
direct pilot roots, registers and explicitly activates generation two, and can
restore exact registered/live generation one. It fails closed on unknown
profile entries or roots, never removes either pilot root, and never adds boot
linkage or broader service ownership. Its failure-injection modes are accepted
only inside a systemd-nspawn container.

The exact failure-injection derivation
`/nix/store/0llhzgyraq4gr7m4agbv8wbvs7xdcql2-container-test-dgx-root-canary-generation-switch-transaction.drv`
**passed** on 2026-09-02. Its hash-valid output is
`/nix/store/l5s5m3q4bd338jflq1abycajwxrfbj5v-container-test-dgx-root-canary-generation-switch-transaction`,
with hash
`sha256:01zxs9x67jgp5ifskcvkr8lihddw886ysqcqgaaw3v6dr9f18766`. All eleven
pre-state, partial-failure, activation-failure, exact-switch, fail-closed,
idempotent-rollback, and cleanup subtests completed. The prior three disposable
derivations remain unchanged.

Independent host postflight found exact `ACTIVE_REGISTERED_RETAINED` generation
one, the host generation-two pilot root absent, all seven protected services
active with no pending reload, systemd running with zero failed units, a healthy
GPU, and healthy sanitized Tailscale SSH. The exact SBOM, state transitions,
failure matrix, and authority boundary are in the
[transaction plan](validation/2026-09-02-generation-switch-transaction-plan.md);
the exact output and host evidence are in the
[container-test result](validation/2026-09-02-generation-switch-transaction-container-test.md).

That pass permitted design of the separate live pilot. The repository now has
`scripts/snapshot-root-generation-switch.sh`,
`scripts/switch-root-canary-generation-pilot.sh`, and a whole-record systemd
snapshot parser/regression check. The live wrapper is bound to a clean commit,
a root-owned snapshot no more than 30 minutes old, the exact passed artifacts,
protected-process continuity, an armed ten-minute generation-one rollback, and
exact `KEEP GENERATION TWO` after local-console verification. The complete
state machine and failure boundary are in the
[live plan](validation/2026-09-02-generation-switch-live-plan.md).

Armen created fresh private snapshot `20260902T083437Z`, verified the local
console, and explicitly authorized that exact snapshot. The wrapper switched at
`2026-09-02T08:38:17Z`. Independent read-only postflight found
`ACTIVE_REGISTERED_GENERATION_TWO_RETAINED`: generation two is selected,
upstream-rooted, directly retained, and live; generation one remains registered
and directly retained. Both pilot roots remain, rollback was disarmed before
its service ran, all protected services and Tailscale SSH remained healthy, and
no boot edge or broader ownership appeared. See the
[retained generation-two host record](validation/2026-09-02-generation-switch-host-attempt-1.md).

That generation-two snapshot and live wrapper remain spent even though the
later boot-persistence milestone superseded this as current state. Do not rerun
them, remove either historical generation/root, or invoke their rollback as
cleanup. The current generation-three boundaries are below.

## Boot persistence: generation three retained live and boot-linked

The next repository-only milestone defines exact generation three by inheriting
generation two and changing only two things: the canary gains
`boot-persistence-generation=3`, and
`default.target.wants/system-manager.target -> ../system-manager.target` is
added through the declarative System Manager unit tree. The package set remains
empty, the three managed service definitions are byte-identical, and no
`/run/current-system`, Nix, user, wrapper, PATH, Tailscale, desktop, Docker,
NVIDIA, dashboard, port, or mutable application-state ownership is added.

The exact 13-subtest transaction derivation
`/nix/store/i5skjqyw16qgbvb4azr68msrqfz64d7k-container-test-dgx-root-canary-boot-persistence-transaction.drv`
**passed** on 2026-09-02. Its hash-valid output is
`/nix/store/d3ymf91l07rvai5pzz9ygj3vl3g9xss3-container-test-dgx-root-canary-boot-persistence-transaction`,
with hash
`sha256:0lxm3pjsd4yy9zl49zx6cbydc9iid1i7mdrajkinkfzszg5k7ikn`. The disposable
test covered unretained-candidate refusal, unknown profile/root collisions,
partial-registration and post-activation failures, exact apply and rollback,
duplicate-apply refusal, a first restart proving automatic start, a second
restart proving rollback restored no-boot behavior, and final cleanup.

At the disposable-test milestone, independent host postflight still classified
`sparkle-01` as
`ACTIVE_REGISTERED_GENERATION_TWO_RETAINED`, with the generation-three pilot
root and boot link absent. The exact state machine and authorization boundary
are in the
[transaction plan](validation/2026-09-02-boot-persistence-transaction-plan.md);
the exact artifacts and host evidence are in the
[container-test result](validation/2026-09-02-boot-persistence-transaction-container-test.md).

That PASS authorized design only. The repository then added
`scripts/snapshot-root-boot-persistence.sh` and
`scripts/activate-root-boot-persistence-pilot.sh`, with both exact hashes
pinned by policy. The wrapper requires exact live no-boot generation two,
creates the generation-three pilot root, arms a ten-minute rollback to
generation two before mutation, registers/activates generation three, repeats
protected-service/GPU/Tailscale postflight, and accepts only exact
`KEEP GENERATION THREE` after local-console verification. Rollback removes the
managed boot edge and generation-three profile link while preserving all three
direct roots.

Armen later verified the physical console and explicitly authorized fresh
private snapshot `20260902T110421Z`. The exact wrapper retained, registered,
selected, and activated generation three, passed postflight twice, received
exact confirmation, and disarmed its ten-minute rollback before the rollback
service ran. Independent audit returned
`ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED`: all three numbered
generations and direct roots remain, the upstream root selects generation
three, exact version-1 state contains six paths and three service keys, and the
one reviewed boot edge exists. Protected services, GPU, and Tailscale SSH
remained healthy. See the
[guarded live plan](validation/2026-09-02-boot-persistence-live-plan.md) and
[retained host result](validation/2026-09-02-boot-persistence-host-attempt-1.md).

The activation timer was transient and no host reboot occurred. Snapshot
`20260902T110421Z` is spent; do not rerun either helper against this post-state.

## Persistent first-reboot recovery: real rollback verified and cleaned

The repository now builds an exact temporary recovery bundle for the first real
generation-three reboot. `arm` creates one direct bundle GC root, one private
state file recording the arming boot ID and exact candidates, an exact service
and timer pair, and one `timers.target.wants` edge. It enables but does not start
the timer in the current boot. On the next boot, the production timer waits ten
minutes for exact `KEEP REBOOTED GENERATION THREE`; otherwise it invokes the
tested rollback to exact registered/live no-boot generation two. Rollback
evidence remains until exact `CLEAN ROLLED BACK REBOOT RECOVERY` cleanup.

If the maintenance window is abandoned before reboot, `disarm-preboot` accepts
only exact `DISARM PREBOOT RECOVERY`, requires the original arming boot ID and
the complete exact recovery surface, removes that surface, and re-verifies
unchanged generation three. This closes the gap between arming and a separately
authorized reboot without granting the helper any reboot capability.

The transaction refuses to roll back or confirm until the kernel boot ID
changes. It preserves foreign collisions, owns only exact symlinks and a
root-owned mode-`0600` state file, and cleans only its own partial work. The
bundle pins the three candidates, the reviewed boot transaction, the recovery
transaction, and a reviewed state auditor. Ordinary tools come from Nix, while
host service control deliberately uses the factory systemd implementation.

The current exact lifecycle derivation
`/nix/store/jqmx45mxqqz34d4yjh3186xadb2ai6qx-container-test-dgx-root-canary-reboot-recovery-transaction.drv`
**passed** at `2026-09-02T20:13:44Z`. Its output is
`/nix/store/p0ywhqdf58h5r83z1pah7arba4rqr0ka-container-test-dgx-root-canary-reboot-recovery-transaction`,
with Nix hash
`sha256:0v7i51bmpjghm8v3cly7i82j3ysvk3in17s5av2465wy3zhzmgp8` and SRI hash
`sha256-6L764R+eF0PEVkWfYOOYW/shBYrHUzY2qvDJW1co8Ww=`. All 13 subtests passed,
including three injected partial failures, same-boot refusal, exact same-boot
disarm and re-arm, one restart with automatic rollback, exact
rollback-evidence cleanup, a second restart with confirmed retention, and
final empty manager cleanup. The earlier 12-subtest PASS remains valid
historical evidence for its exact predecessor, but it is superseded as the
current-match gate because it did not prove cancellation of an abandoned
pre-reboot window.

The test also made the runtime distinction explicit: immediately after
activation, all three managed units are active; after a clean boot,
`system-manager.target` and `dgx-setup-canary.service` are active while the
reactivation-only `sysinit-reactivation.target` is inactive. The hash-pinned
auditor exposes a `postboot` mode for that exact state and emits
`ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_REBOOTED_RETAINED`. Its normal
activation-time behavior is unchanged. Recovery paths remain drift unless the
already-verified recovery transaction explicitly invokes the auditor with its
caller-verification mode.

Read the
[recovery transaction plan](validation/2026-09-02-reboot-recovery-transaction-plan.md)
and exact
[container-test result](validation/2026-09-02-reboot-recovery-transaction-container-test.md)
before touching the bundle, auditor, transaction, or test. The host postflight
remained exact pre-reboot generation three, with both recovery units `not-found`
and all recovery paths absent.

The repository now includes hash-pinned
`scripts/snapshot-root-reboot-recovery.sh` and
`scripts/root-reboot-recovery-pilot.sh`. The snapshot helper is read-only with
respect to System Manager/systemd and binds one clean commit, exact live state,
passed test output, protected-service continuity, GPU/Tailscale health, local
console, and the current boot ID. The pilot exposes `arm`, `disarm-preboot`,
`status`, `confirm`, `verify-rolled-back`, and `cleanup-rolled-back`; it has no
reboot action. Read the
[live recovery plan](validation/2026-09-03-reboot-recovery-live-plan.md) before
using either helper.

The separately authorized live attempt used snapshot `20260902T204546Z` and
then rebooted outside the helpers. The persistent timer started on the new boot
and its ten-minute deadline expired before a valid confirmation arrived.
Automatic rollback restored exact registered/live no-boot generation two.
Snapshot-bound `verify-rolled-back` passed, exact cleanup removed the recovery
surface, and independent classification returned
`ACTIVE_REGISTERED_GENERATION_TWO_TRIPLE_RETAINED`. All three direct pilot
roots remain; generation three's numbered profile link and boot edge are
absent; no recovery timer is armed.

The first correctly formed confirmation command began two seconds after the
deadline and also exposed a false assumption: after a clean boot,
`nix-daemon.service` may be cleanly inactive while `nix-daemon.socket` is
active/listening. Updated helpers accept that normal postboot state while
retaining strict same-boot continuity. `scripts/dgx-recovery` now supplies the
short operator interface and deliberately has no reboot action. Full evidence
is in the
[first real reboot record](validation/2026-09-03-reboot-recovery-host-attempt-1.md).

The next mutation is a hash-pinned no-reboot restoration helper that requires
this exact generation-two state, a clean commit, a new private snapshot,
independent console access, a transient ten-minute rollback, repeated health
checks, and exact `RESTORE GENERATION THREE` / `KEEP RESTORED GENERATION THREE`
confirmations. Any later recovery arming and reboot remain separate gates.

## Defaults we rejected

Upstream's nominally empty configuration is broader than this project's empty
root role. The repository explicitly disables or removes:

- Nix configuration ownership and `/etc/nix/nix.conf` generation;
- `userborn.service` and all user/group/passwd/shadow ownership;
- setuid/setgid wrappers and the wrapper mount;
- global system packages;
- login-wide PATH/XDG hooks in `/etc/profile.d` and `/etc/environment.d`;
- `system-manager-path.service`;
- managed tmpfiles configuration;
- `/run/current-system`; and
- the boot-time `default.target` link in the base generations.

Generation three is the narrow, separately approved exception to the last
item. It adds exactly one declarative boot edge without enabling any other
rejected default.

The policy check fails if these defaults return, if any unexpected service or
`/etc` entry appears, or if Nix 2.34.8 or a real `userborn` runtime re-enters the
closure.

## Local empty-tmpfiles safety patch

System Manager 1.1.0 collects this configuration's managed files below
`/etc/tmpfiles.d`, then unconditionally runs `systemd-tmpfiles --create
--remove`. When the collection is empty, omitting config-file arguments tells
`systemd-tmpfiles` to process every tmpfiles rule visible on the machine. That
would cross this repository's boundary and act on factory-owned configuration.

The first root-local disposable-container attempt on 2026-08-24 exposed this:
activation reached the manager, installed its canary tree inside the container,
then global tmpfiles processing tried to change journal-directory modes and the
container rejected it. The test derivation failed and destroyed the container.
Postflight checks confirmed every canary, unit, state, profile, and GC-root path
on the host remained absent; Nix, Tailscale, and GDM remained active with no
pending reload.

The repository applies
`patches/system-manager/skip-empty-tmpfiles.patch` only when the package name is
`system-manager` and the version is exactly `1.1.0`. It returns successfully
without spawning `systemd-tmpfiles` when no managed config exists. The patch is
part of the manager derivation and machine-readable manifest, and closure policy
requires that exact patched package. A future manager version will not inherit
the patch silently: evaluation/build policy must be reviewed and adjusted.

The exact patched disposable test subsequently passed on 2026-08-24. It proved
that the patch skips the global invocation, the unmanaged tmpfiles sentinel is
never processed, protected files remain byte-identical, and activation plus
deactivation stay within the reviewed canary boundary. See the
[durable validation record](validation/2026-08-24-container-test.md) for the
exact derivation, output, warning disposition, and clean host postflight.

## Runtime versus lock graph

Stable Nixpkgs currently exposes Nix 2.34.8. System Manager normally wraps its
engine with that `pkgs.nix`, even though this host runs verified Nix 2.35.2. The
repository therefore pins the official Nix 2.35.2 release flake independently
and overlays only System Manager's private wrapper. This does not update or own
the host Nix installation. The final closure contains Nix 2.35.2 and contains
no Nix 2.34.8.

Upstream's deactivation script also adds `services.userborn.package` to `PATH`
unconditionally. Because this canary forbids user ownership, that package is an
empty `disabled-userborn` directory. The real `userborn` binary is absent from
the runtime closure.

`flake.lock` still records System Manager's `userborn` source input and both
upstreams' development/test inputs. Those records make source evaluation
reproducible; they are not services or runtime packages. Do not confuse lock
graph membership with installation or activation.

No persistent substituter or trusted key was added for System Manager. Builds
use the host's existing Nix cache policy.

## Read-only evaluation and SBOM

Run from the repository root:

```bash
./scripts/check.sh

nix --extra-experimental-features "nix-command flakes" \
  eval --json .#lib.dgxRootManagerManifest.aarch64-linux
```

The first command evaluates invariants only. The second emits the exact manager
revision, private Nix runtime, ownership surface, declared state/registration
paths, and proof that evaluation/build performs no activation, registration, or
pilot-root creation. The top-level `activated`, `registration.performed`, and
pilot-root `created` booleans are declarative evaluation side-effect flags, not
probes of mutable host state. The separately named
`guardedFirstGeneration.liveRegistration` record is dated operational evidence.
The [host-canary attempt 3 record](validation/2026-09-01-host-canary-attempt-3.md)
is the original activation authority; the
[first-registration attempt 3 record](validation/2026-09-01-first-registration-host-attempt-3.md)
is the first-registration authority; and the
[retained generation-two host record](validation/2026-09-02-generation-switch-host-attempt-1.md)
is the historical generation-two authority. The
[retained generation-three host record](validation/2026-09-02-boot-persistence-host-attempt-1.md)
is the current full live-state authority. The
[boot-persistence container-test result](validation/2026-09-02-boot-persistence-transaction-container-test.md)
is repository/test evidence for the pre-activation milestone and explicitly
records that its disposable test left the then-live host on generation two.

Review missing builds without realizing anything:

```bash
nix --extra-experimental-features "nix-command flakes" \
  build --dry-run --no-link \
  .#root-system-canary \
  .#root-system-canary-generation-two \
  .#root-system-canary-generation-three-boot \
  .#checks.aarch64-linux.root-manager-policy \
  .#checks.aarch64-linux.root-canary-container \
  .#checks.aarch64-linux.root-canary-boot-persistence-transaction-container \
  .#checks.aarch64-linux.root-canary-generation-switch-transaction-container \
  .#checks.aarch64-linux.root-canary-registration-container \
  .#checks.aarch64-linux.root-canary-registration-transaction-container
```

An explicitly approved no-link runtime build is:

```bash
nix --extra-experimental-features "nix-command flakes" \
  build --no-link \
  .#root-system-canary \
  .#checks.aarch64-linux.root-manager-policy
```

This realizes store objects only. It does not create a profile, GC root, host
link, state file, unit, or service.

## Isolated activation/rollback test

The flake defines an Ubuntu 24.04 `systemd-nspawn` test that activates and
deactivates the canary inside a disposable Nix build sandbox. It verifies:

- protected Nix/passwd/group/shadow files are byte-identical;
- no global PATH hooks, `/run/current-system`, boot link, users, or wrappers;
- exactly five filesystem entries become managed: the canary, three units, and
  the target-wants dependency symlink;
- an unmanaged container-only tmpfiles rule is never processed during activation
  or deactivation;
- no System Manager profile or GC root is registered;
- deactivation removes the canary and units; and
- the residual manager state is an empty version-0 record.

The test harness requires the Nix `uid-range` system feature plus
`auto-allocate-uids`. UID-range builds are automatically isolated with cgroups,
so the Nix `cgroups` experimental feature is also required. Neither experimental
feature is persistently enabled for the daemon.

Nix 2.35 deliberately removes `experimental-features` from client-to-daemon
setting overrides. Passing these flags through the running daemon therefore
causes it to ignore `auto-allocate-uids` and reject `cgroups`. The reviewed
helper avoids that mismatch by using the same store directly as root with
`--store local`; the ordinary user cannot perform that direct-store build.

The initial 2026-08-24 invocation used the daemon path and stopped before the
container builder ran. It created no System Manager link, unit, profile, GC root,
manager state, or service change. Nix did create its empty UID-allocation lock
at `/nix/var/nix/userpool2/slot-0` and a stale temporary-root record under
`/nix/var/nix/temproots/<exited-pid>`. The latter is not a permanent GC root;
Nix removes stale temporary-root records during a future garbage-collection scan.
No manual cleanup was attempted. That preflight failure is why the direct-store
path is explicit.

The next root-local attempt reached activation and found the upstream empty-list
tmpfiles bug documented above. Its container was also disposable and the host
again remained untouched.

The exact patched derivation then passed on 2026-08-24. Activation managed only
the five allowlisted paths and three service keys, skipped the unmanaged
tmpfiles sentinel, preserved all protected-file hashes, registered no generation
or GC root, and deactivated cleanly inside the disposable container. Read-only
host postflight found no canary, unit, state, profile, or GC-root artifact and
found Nix, Tailscale, and GDM healthy with no pending reload.

The reviewed helper command for this separately authorized test is:

```bash
sudo ./scripts/test-root-canary.sh
```

Do not rerun it during an ordinary audit. A changed test derivation invalidates
the recorded pass and requires separate authorization.

The reviewed helper invokes `/nix/var/nix/profiles/default/bin/nix` against the
local store with `auto-allocate-uids` and `cgroups` enabled only in that root
process. It also sets `NIX_USER_CONF_FILES=/dev/null` for that command so root's
personal Nix configuration cannot add hidden settings; system-wide
`/etc/nix/nix.conf` is still read, and all temporary features remain explicit.
That isolation does not suppress the observed top-level Nix 2.35.2 warning about
`auto-allocate-uids`. The warning was absent from the successful derivation log
and non-fatal; completion of the UID-range/cgroup container test proves the
required capability was effective. The helper does not edit `nix.conf`,
stop/reconfigure/restart the daemon, create a profile, or activate the host.
Like every build, it may add test paths and build records to the Nix store.

UID allocation uses persistent lock files under `/nix/var/nix/userpool2`;
cgroup cleanup tracking may remain under
`/nix/var/nix/cgroups/<uid>`. These are Nix operational bookkeeping, not a
System Manager generation or host configuration. The one-time dry-run was
943.7 MiB download and 3.9 GiB unpacked, primarily the Ubuntu rootfs,
Rust/build tools, Python test driver, and systemd utilities. Those are test
dependencies, not the 230.0 MiB runtime closure and not a system profile.

## Active-canary and future activation gates

The exact candidate is retained active as documented above. The inactive-state
preflight and guarded activation helper now correctly encounter their declared
paths as collisions; do not rerun them merely to audit the active canary.

For any future activation, reactivation, or changed candidate, do not proceed
merely because evaluation, build, or the container test passes. The maintenance
window still requires all of the following:

1. independently verified local console/recovery access—not only Tailscale SSH;
2. an exact collision report for every declared `/etc` and systemd path;
3. snapshots of the relevant `/etc`, System Manager state, profile, and GC-root
   paths;
4. live checks for Tailscale, GDM/GNOME, Nix daemon, Docker, and NVIDIA services;
5. the manifest-declared pilot GC root retaining the exact already-built output;
6. a timed rollback plan using that exact retained output; and
7. Armen's explicit authorization for this activation only.

The reusable automatic inspection is:

```bash
./scripts/preflight-root-canary.sh
```

It is read-only, expects an inactive canary, and deliberately leaves the manual
console gate on HOLD. The dated
[host preflight record](validation/2026-08-24-host-preflight.md) contains
the current collision/health evidence, private snapshot helper, exact candidate,
and prepared ten-minute transient rollback sequence. None of those prepared
commands is activation authorization.

Low-level deactivation for an already-activated, exact built output is:

```bash
sudo /nix/store/<reviewed-system-manager-output>/bin/deactivate
```

Deactivation is not an uninstall: the empty state file remains, and any future
registered generation/profile requires separate cleanup review. Never replace
the placeholder with a floating flake reference in a rollback command.

### Guarded live-pilot helper

For the exact `sparkle-01` candidate recorded above, the reviewed live helper
combines the snapshot check, collision and health gates, direct pilot GC root,
ten-minute rollback timer, low-level activation, and exact postflight:

```bash
sudo ./scripts/activate-root-canary-pilot.sh \
  "$PWD/inventory/sparkle-01/raw/system-manager-canary/<snapshot-timestamp>"
```

The helper is intentionally hard-coded to the exact tested store output and
refuses another host, candidate, snapshot location, unexpected artifact, or
non-interactive terminal. It accepts a prior residual state only when it is the
exact empty version-0 rollback record, and accepts a retained pilot root only
when it points directly to this exact candidate. A fresh snapshot records those
two exact conditions without deleting them. The activation helper requires that
snapshot to match the live residuals and be no more than 30 minutes old. It
never calls `register-profile`.
Any failure after the timer is armed leaves the timer in control and preserves
the pilot GC root.
After automatic postflight passes, it allows five minutes for a person to test
the independent local console and type the exact `KEEP CANARY` confirmation;
only then does it rerun postflight and stop the rollback timer. The pilot root
remains while the canary is active.

A candidate change makes this helper stale. Update its exact path only together
with the manifest, closure review, newly authorized disposable test, host
preflight, and a fresh same-window snapshot.

## Updates

`scripts/update-dependencies.sh` advances the matching System Manager release
branch and reruns its evaluation, closure-policy, and no-link runtime gates. The
update remains valid only while the exact-version overlay applies the reviewed
patch and the manifest/audit retain its hash and no-global-tmpfiles policy. An
upstream version change is a mandatory reassessment, not permission to drop or
blindly carry the patch. The root-assisted container test remains the explicit
helper above. Any input, patch, ownership surface, test, or closure change
invalidates the recorded pass and requires a newly authorized disposable test
rather than being accepted automatically.

The `nix-release` input is an exact tag and is intentionally not auto-advanced.
Audit and activate a new host Nix runtime through `root/nix/README.md` first;
then update the private manager runtime to that same reviewed release in a
separate repository change. Availability is not update authorization.
