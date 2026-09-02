# System Manager first-reboot live recovery plan — 2026-09-03

> Historical execution plan. The separately authorized reboot was performed,
> its confirmation deadline expired, automatic generation-two rollback passed,
> and exact verification/cleanup completed. Current authority is the
> [host attempt record](2026-09-03-reboot-recovery-host-attempt-1.md). The plan
> below preserves the pre-execution gates and exact inputs.

## Status and authorization boundary

**REPOSITORY DESIGN, HASH PINNING, AND DISPOSABLE PROOF COMPLETE. HOST RECOVERY
IS UNARMED. NO HOST REBOOT IS AUTHORIZED.**

The current host remains exact
`ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED`. Generations one,
two, and three remain registered and directly retained; generation three is
selected, upstream-rooted, live, and connected to `default.target` by the one
reviewed boot edge. No recovery path or recovery unit exists on the host, and
the host has not rebooted since generation-three activation.

This plan authorizes repository evaluation, inert builds, documentation, and
read-only host checks. It does not authorize creating a private live snapshot,
installing or enabling recovery, rebooting, confirming a reboot, accepting an
automatic rollback, cleaning rollback evidence, removing a generation/root, or
changing any factory service.

## Exact reviewed evidence

| Field | Value |
| --- | --- |
| Repository base commit | `4d662ea33ebadd340812c13cebf34b367d849e85` |
| Generation one | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| Generation two | `/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager` |
| Generation three | `/nix/store/w8kn2idc0ix6x1024qphv2fvmaf664d7-system-manager` |
| Recovery transaction SHA-256 | `b1f04f39169cc000b5a532545439693bafd9d6c62d0190e9aac2c231394a6be9` |
| Postboot auditor SHA-256 | `19cac3ba416dc3705c9dc1a996afb82840e8f4bc2d657a78f969f3f42cfddb12` |
| Production bundle | `/nix/store/wpikhcgj77ws90j4ivdp3498mlmffyax-dgx-root-reboot-recovery` |
| Production bundle derivation | `/nix/store/h4qaivg6jpf1fbgz8v8dmdi0j3xmgmps-dgx-root-reboot-recovery.drv` |
| Production rollback delay | `OnBootSec=10min` |
| Current test derivation | `/nix/store/jqmx45mxqqz34d4yjh3186xadb2ai6qx-container-test-dgx-root-canary-reboot-recovery-transaction.drv` |
| Current test output | `/nix/store/p0ywhqdf58h5r83z1pah7arba4rqr0ka-container-test-dgx-root-canary-reboot-recovery-transaction` |
| Current output hash | `sha256:0v7i51bmpjghm8v3cly7i82j3ysvk3in17s5av2465wy3zhzmgp8` |
| Snapshot helper | `scripts/snapshot-root-reboot-recovery.sh` |
| Snapshot helper SHA-256 | `fffb2e62c9cf93ce62a22c86bcf8331ff8d930fefedaeb5fbf63668e1452ddfd` |
| Lifecycle helper | `scripts/root-reboot-recovery-pilot.sh` |
| Lifecycle helper SHA-256 | `4a67bdd4fc2c1195b88cce2122a047059ca086f803990fcaaf638fb95774c865` |
| Systemd snapshot parser SHA-256 | `1123fe7efa54c21aaa9b1609ba132bdbe3a66a50deff41da33e826eb37d332af` |
| Parser regression SHA-256 | `d9829ce6200752e0bb93810b2cc59cc5f137483abf4dc5a5f9ea491826585009` |
| Disposable result | 13 subtests, two restarts, exit status 0 |
| Host recovery state | absent and unarmed |
| Host reboot state | not performed |

The exact transaction plan and current PASS are in
[the transaction plan](2026-09-02-reboot-recovery-transaction-plan.md) and
[container-test result](2026-09-02-reboot-recovery-transaction-container-test.md).
The Thunderbird/Netplan unit-graph drift encountered immediately before the
current PASS is dispositioned in
[the guarded reload record](2026-09-03-thunderbird-unit-graph-reload.md).

## Helper boundary

The snapshot helper writes only a new root-owned mode-`0700` directory under
`inventory/sparkle-01/raw/system-manager-reboot-recovery/`. It requires:

- a clean committed repository;
- exact Nix 2.35.2 and the exact evaluated candidates/bundle/test/policy;
- exact live generation-three state and all six managed links;
- every recovery path absent and both recovery units `not-found`;
- all prior transient rollback units absent;
- all seven protected services active, reload-clean, with live process and
  start-time evidence;
- systemd running with zero failed units;
- a working GPU query and sanitized healthy Tailscale/Tailscale SSH booleans;
  and
- an active graphical `seat0` as independent local-console evidence.

It snapshots the exact manager state, profile/root/link surface, protected-file
hashes, protected-service properties, sanitized health, current kernel boot ID,
helper copies/hashes, passed test output/hash, and policy derivation. It performs
no daemon reload, service operation, recovery installation, registration,
activation, or reboot.

The lifecycle helper accepts exactly these actions:

| Action | Exact purpose |
| --- | --- |
| `arm` | Revalidate the fresh snapshot and clean commit, require `ARM PERSISTENT RECOVERY`, install and verify the exact persistent recovery surface, but never reboot |
| `disarm-preboot` | On the original boot only, require `DISARM PREBOOT RECOVERY`, remove exact recovery, and retain unchanged generation three |
| `status` | Read and verify the exact preboot, postboot-waiting, rolled-back, or completed state without mutation |
| `confirm` | On a new boot only, require `KEEP REBOOTED GENERATION THREE`, retain exact booted generation three, and remove recovery |
| `verify-rolled-back` | Verify the automatic exact registered/live no-boot generation-two rollback while retaining evidence |
| `cleanup-rolled-back` | After verification, require `CLEAN ROLLED BACK REBOOT RECOVERY` and remove only exact recovery evidence |

The helper contains no `reboot`, `shutdown`, `systemctl reboot`, or equivalent
action. A successful `arm` grants no reboot authority. If arming succeeds but
the maintenance window is canceled, use its exact same-boot disarm action; do
not leave recovery silently armed.

## Staged live sequence

Each stage is a distinct authority boundary:

1. Commit the exact reviewed design and pass all repository/skill checks.
2. With the physical console available, separately authorize creation of one
   fresh private snapshot and run only the snapshot helper.
3. Review the emitted snapshot path and explicit arming statement. Separately
   authorize arming bound to that snapshot, then run only the lifecycle
   helper's `arm` action and enter its exact phrase locally.
4. Verify `status` on the original boot. At this point the timer is enabled for
   the next boot but inactive now. Stop here unless a separate reboot
   authorization is given.
5. If reboot is canceled, run `disarm-preboot` with its exact phrase. If reboot
   is authorized, reboot through a separately chosen/operator-executed command;
   no repository recovery helper performs it.
6. On the new boot, use the snapshot-bound helper copy. If exact generation
   three and protected health are good before the ten-minute deadline, run
   `confirm` and enter its exact phrase. If not confirmed, the persistent timer
   automatically restores exact registered/live no-boot generation two.
7. If rollback occurred, first run `verify-rolled-back`; cleanup remains a
   separate exact-phrase action so evidence is not erased before review.

Any changed boot ID before arming, expired snapshot, dirty commit, changed
helper/hash/derivation, pending daemon reload, service/process drift, failed
health gate, unknown recovery artifact, or mismatched state fails closed.

## Next authorized boundary

The next possible host mutation is recovery arming, but it is not authorized by
this document or by the disposable PASS. It requires a fresh snapshot created
from the final clean commit, independent local-console verification, and Armen's
explicit authorization naming that snapshot. Reboot requires another explicit
authorization after exact preboot status passes.
