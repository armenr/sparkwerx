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
confirmation. The exact five-path/three-service canary is currently active. No
System Manager profile has been registered, no boot link exists, and no broader
root role is active.

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
| Registration lifecycle container test | **PASS** for the exact recorded derivation; host remained unregistered |
| Guarded first-registration transaction test | **PENDING** root-assisted disposable execution; design/static evaluation pass |
| Host activation | Attempt 3 retained and independently postflight-verified; active, unregistered, not boot-linked |

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
is the current live-state authority.

Do not rerun the inactive-state preflight or activation helper while this
canary remains active, remove its pilot root, register a generation, add boot
linkage, or broaden its role without a new reviewed plan and explicit
authorization.

## Exact canary ownership

The evaluated configuration has no global packages and declares only:

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
It is not linked into the factory default target and cannot start at boot.

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

Both logical registration paths and every numbered generation link must remain
absent until live generation registration receives explicit approval.

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

## Guarded first-generation transaction: staged, test pending

The reviewed design now wraps the exact upstream helper with a strict
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

The distinct disposable failure-injection derivation currently evaluates to
`/nix/store/lxnykcyvjn18pdv7y9rr1ryhvjgicazg-container-test-dgx-root-canary-registration-transaction.drv`.
Its design is recorded in the
[first-registration transaction plan](validation/2026-09-01-first-registration-transaction-plan.md).
Static evaluation passes, the prior two passed derivations remain unchanged,
and the live host remains `ACTIVE_RETAINED`. Root-assisted execution is still
pending:

```bash
sudo ./scripts/test-root-registration-transaction.sh
```

Do not run the private snapshot or live wrapper merely because this disposable
test later passes. After a recorded hash-valid PASS, a live attempt would still
require a clean committed tree, a fresh root-owned registration snapshot,
independent console access, an exact ten-minute registration-only rollback, and
new authorization bound to that snapshot. The staged helpers are
`scripts/snapshot-root-registration.sh` and
`scripts/register-root-canary-pilot.sh`. The live wrapper creates no boot link
and performs no activation; it retains registration only after repeated
postflight and the exact `KEEP REGISTRATION` confirmation.

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
- the boot-time `default.target` link.

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
pilot-root creation. Its `activated`, `performed`, and `created` booleans are
declarative side-effect flags, not probes of mutable host state. The
[attempt 3 record](validation/2026-09-01-host-canary-attempt-3.md) is the current
live-state authority.

Review missing builds without realizing anything:

```bash
nix --extra-experimental-features "nix-command flakes" \
  build --dry-run --no-link \
  .#root-system-canary \
  .#checks.aarch64-linux.root-manager-policy \
  .#checks.aarch64-linux.root-canary-container \
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
