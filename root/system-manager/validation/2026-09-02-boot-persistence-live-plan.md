# Guarded live boot-persistence activation plan — 2026-09-02

## Status and authority boundary

**LIVE ACTIVATION EXECUTED AND RETAINED; HOST REBOOT NOT AUTHORIZED OR
PERFORMED.**

This milestone defined and validated the host snapshot helper and live wrapper
for an exact System Manager generation-two to generation-three activation.
Armen later created and authorized fresh snapshot `20260902T110421Z`; the exact
wrapper completed and retained generation three. This plan never authorized a
host reboot, and none occurred.

The current host is
`ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED`: generation three is
selected, upstream-rooted, directly retained, live, and linked into
`default.target`; generations one and two remain registered and directly
retained. The first real host reboot remains a separate milestone.

## Exact reviewed inputs

| Input | Exact value |
| --- | --- |
| Generation one | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| Generation two | `/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager` |
| Generation three | `/nix/store/w8kn2idc0ix6x1024qphv2fvmaf664d7-system-manager` |
| Transaction | `scripts/root-boot-persistence-transaction.sh` |
| Transaction SHA-256 | `53eb8c4d03a4c24764f519e358f3c5c813e66f189efc07e50f82cd19841d8288` |
| Passed test derivation | `/nix/store/i5skjqyw16qgbvb4azr68msrqfz64d7k-container-test-dgx-root-canary-boot-persistence-transaction.drv` |
| Passed test output | `/nix/store/d3ymf91l07rvai5pzz9ygj3vl3g9xss3-container-test-dgx-root-canary-boot-persistence-transaction` |
| Passed output hash | `sha256:0lxm3pjsd4yy9zl49zx6cbydc9iid1i7mdrajkinkfzszg5k7ikn` |
| Snapshot helper | `scripts/snapshot-root-boot-persistence.sh` |
| Snapshot helper SHA-256 | `bb726566b5e11ed466aaab0ab7ab12e3f40f7f93af4561767bfbdb500f4640ff` |
| Live wrapper | `scripts/activate-root-boot-persistence-pilot.sh` |
| Live wrapper SHA-256 | `464f2b8283fbed336722ae96ee3786d3188b1cfba09f588974dd9381b8a58e70` |
| Snapshot parser | `scripts/systemd-snapshot-property.sh` |
| Parser SHA-256 | `1123fe7efa54c21aaa9b1609ba132bdbe3a66a50deff41da33e826eb37d332af` |
| Parser regression SHA-256 | `d9829ce6200752e0bb93810b2cc59cc5f137483abf4dc5a5f9ea491826585009` |

The flake manifest and fixed-output policy assert all helper hashes. The
snapshot copies the exact passed transaction and parser into its private
root-owned directory; the live wrapper executes those immutable snapshot
copies rather than a mutable transaction path in the worktree.

## Exact intended live delta

Generation three inherits generation two and changes only:

- the canary identity line `boot-persistence-generation=3`; and
- the System Manager-owned symlink
  `/etc/systemd/system/default.target.wants/system-manager.target ->
  ../system-manager.target`.

The global package set remains empty, the three managed service definitions
remain byte-identical, and `system-manager.linkCurrentSystem` remains false.
The pilot does not take ownership of Nix, users, wrappers, PATH, Tailscale,
GDM, Docker, NVIDIA, DGX Dashboard, a port, or mutable application state.

## Required same-window gates

A live invocation requires all of the following:

1. a clean committed repository matching the pinned helper hashes;
2. the exact passed disposable derivation/output/hash still valid and current;
3. exact live no-boot generation two with generations one/two and their direct
   roots intact, and no generation-three profile link/root;
4. all seven protected factory/access services active, unrestarted, loaded
   from their snapshotted fragments, and requiring no daemon reload;
5. systemd running with zero failed units, a responsive NVIDIA GPU, and
   sanitized healthy Tailscale/Tailscale SSH state;
6. physical display, keyboard, and local terminal independently verified;
7. a fresh private root-owned mode-`0700` snapshot no more than 1,800 seconds
   old; and
8. explicit authorization from Armen bound to that exact snapshot.

No authorization from the disposable test or an earlier generation milestone
carries across this boundary.

## Private snapshot

The snapshot helper accepts one new directory below:

`inventory/sparkle-01/raw/system-manager-boot-persistence/`

It records the clean commit, exact candidates, policy derivation, helper hashes,
passed test evidence, complete profile/root/boot pre-state, exact manager state,
resolved managed links, protected-file hashes, whole-record protected-service
continuity, and sanitized system/GPU/Tailscale health. It copies only the exact
transaction and systemd parser needed for rollback.

Snapshot creation performs no candidate retention, registration, activation,
boot-link creation, daemon reload, service operation, or reboot. An incomplete,
modified, moved outside the reviewed root, non-private, or older-than-30-minute
snapshot is unusable.

## Live state machine

| Stage | Exact state |
| --- | --- |
| Initial | Generation two selected/upstream-rooted/live; generations one/two directly retained; generation three and boot edge absent |
| Retain | Create only `dgx-setup-root-canary-boot-persistence-pilot ->` exact generation three |
| Arm | Start `dgx-root-boot-persistence-rollback.timer` for ten minutes, invoking the exact copied transaction's `rollback-boot` action |
| Activate | Register, select, upstream-root, and explicitly activate exact generation three |
| Postflight | Generation three selected/upstream-rooted/live; all three candidates directly retained; exact one boot edge present; protected services unchanged |
| Confirm | After local-console verification, accept only `KEEP GENERATION THREE`, repeat postflight, then stop the rollback timer |
| Roll back | Activate generation two first, select/upstream-root it, remove only exact `system-manager-3-link`, and remove the managed boot edge; keep all three direct roots |

The wrapper never begins registration or activation until the rollback timer is
active, waiting, and bound to the exact copied transaction, action, and three
candidates.

## Failure behavior

- Failure before generation-three retention changes nothing.
- Failure after retention but before the timer leaves the exact generation-three
  root for explicit inspection and later separately authorized cleanup.
- Failure, disconnect, Ctrl-C, wrong confirmation, or confirmation timeout after
  the timer is armed leaves rollback armed.
- The tested transaction reconciles known partial registration and activation
  failures back to exact generation two; the still-armed timer safely verifies
  or repeats that exact rollback.
- Any unknown profile entry, root, target, managed path, service inventory,
  candidate, snapshot record, protected-file hash, protected-process change,
  health failure, or boot-edge drift is a hard stop.

## Critical no-reboot boundary

The activation rollback timer is a transient unit under `/run`; it is
independent of Tailscale but does **not** survive a host reboot or sudden power
loss. Therefore the live wrapper:

- performs no reboot;
- tells the operator not to reboot during the guarded window; and
- does not claim that a retained activation proves real-host boot recovery.

After successful `KEEP GENERATION THREE`, generation three and its boot edge
would remain live, but a first intentional reboot would still require a
separate persistent recovery design, fresh snapshot/authorization, physical
console availability, post-boot classification, and a rollback path that
remains available if Tailscale does not return. This plan grants no reboot
authority.

## Validation before live review

Before presenting commands for a live snapshot:

- both new helpers and the exact transaction must pass `bash -n`;
- the whole-record systemd parser regression must pass;
- helper hashes must match the manifest and this plan;
- `nix flake check --no-build`, the root-manager policy build, and
  `./scripts/check.sh --no-write-lock-file` must pass;
- the exact prior disposable boot-persistence derivation/output/hash must remain
  current and valid; and
- an independent read-only host audit must still report exact generation two,
  absent generation-three root/link, and absent host boot edge.

Repository validation changes no live System Manager, service, root, profile,
or boot state. Work stops at the fresh-snapshot/explicit-authorization gate.

## Repository validation result

At `2026-09-02T10:57:33Z`, against base commit
`f57f28d6f7371379c19019d6fca82feb819c7339`:

- both new helpers and the exact transaction passed `bash -n`;
- `nix flake check --no-build --no-write-lock-file` passed;
- the root-manager policy built successfully with both helper hashes pinned;
- `./scripts/check.sh --no-write-lock-file` passed;
- the whole-record systemd parser regression passed;
- the built-in skill validator reported `Skill is valid!` for
  `dgx-spark-ops`;
- the exact prior test derivation and output remained Nix-valid, with the exact
  recorded deriver and output hash;
- helper SHA-256 values remained `bb726566…` (snapshot) and `464f2b82…`
  (activation); and
- independent read-only host postflight returned:

  ```text
  STATE=ACTIVE_REGISTERED_GENERATION_TWO_RETAINED
  GEN3_ROOT=ABSENT
  GEN3_PROFILE=ABSENT
  BOOT_LINK=ABSENT
  ```

These results validate repository design only. They created no host root,
profile link, activation, boot edge, rollback timer, service change, or reboot.

## Live execution result

Armen verified the physical console and explicitly authorized private snapshot
`20260902T110421Z`. At `2026-09-02T11:16:42Z`, the wrapper retained the exact
generation-three candidate, armed the exact ten-minute generation-two
rollback, registered/selected/activated generation three, and passed automatic
postflight. The exact confirmation path repeated postflight and stopped the
timer at `11:16:50Z`; the rollback service did not run.

Independent read-only observation found the exact three-generation profile and
root surface, version-1 six-path/three-service state, both canary markers, the
one reviewed boot edge, all rejected broader paths absent, zero failed units,
healthy protected services/GPU/Tailscale SSH, and classifier result
`ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED`. The host boot time
predates the activation, so no reboot occurred. The full evidence and its
transcript/inference boundary are recorded in the
[retained host result](2026-09-02-boot-persistence-host-attempt-1.md).

The snapshot is spent. Do not rerun either helper against the retained
post-state. The next boundary is a separately designed, snapshot-bound,
persistent-recovery first-host reboot; this activation grants no reboot,
rollback, cleanup, root retirement, or broader-ownership authority.
