# System Manager first-reboot recovery — host attempt 1

Date: 2026-09-03 local (`Asia/Yerevan`), 2026-09-02 UTC

Status: **real reboot completed; ten-minute deadline expired; automatic exact
generation-two rollback passed; rollback verified and recovery surface cleaned**

## Authority and exact inputs

Armen created private snapshot
`inventory/sparkle-01/raw/system-manager-reboot-recovery/20260902T204546Z`,
verified the independent local console, armed the exact persistent recovery
surface, checked its preboot status, and then separately authorized the reboot:

> I authorize the first reboot of sparkle-01 using recovery snapshot
> 20260902T204546Z.

The clean repository authority was commit
`0baad0d4811dcbf0592754130fef8cf13bb50417`. The exact reviewed inputs were:

| Input | Exact value |
| --- | --- |
| Generation one | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| Generation two | `/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager` |
| Generation three | `/nix/store/w8kn2idc0ix6x1024qphv2fvmaf664d7-system-manager` |
| Recovery bundle | `/nix/store/wpikhcgj77ws90j4ivdp3498mlmffyax-dgx-root-reboot-recovery` |
| Recovery transaction test | `/nix/store/jqmx45mxqqz34d4yjh3186xadb2ai6qx-container-test-dgx-root-canary-reboot-recovery-transaction.drv` |
| Passed output | `/nix/store/p0ywhqdf58h5r83z1pah7arba4rqr0ka-container-test-dgx-root-canary-reboot-recovery-transaction` |
| Passed output hash | `sha256:0v7i51bmpjghm8v3cly7i82j3ysvk3in17s5av2465wy3zhzmgp8` |
| Snapshot helper SHA-256 | `fffb2e62c9cf93ce62a22c86bcf8331ff8d930fefedaeb5fbf63668e1452ddfd` |
| Lifecycle helper SHA-256 | `4a67bdd4fc2c1195b88cce2122a047059ca086f803990fcaaf638fb95774c865` |

The snapshot and arming commands did not reboot the host. The operator executed
the separately authorized reboot outside the repository helpers.

## Timeline and outcome

| UTC | Local time | Event |
| --- | --- | --- |
| `2026-09-02T20:49:28Z` | 00:49:28 | Recovery arming completed; the timer was enabled but inactive on the original boot |
| `2026-09-02T21:06:03Z` | 01:06:03 | `sparkle-01` booted with generation three linked at boot |
| `2026-09-02T21:06:09Z` | 01:06:09 | Persistent ten-minute recovery timer started |
| `2026-09-02T21:16:04Z` | 01:16:04 | Deadline fired and automatic rollback began |
| `2026-09-02T21:16:05Z` | 01:16:05 | Exact generation-two rollback completed successfully |
| `2026-09-02T21:16:06Z` | 01:16:06 | First correctly formed confirmation command began, two seconds after the deadline |
| `2026-09-02T21:23:39Z` | 01:23:39 | Snapshot-bound `verify-rolled-back` passed |

The first two postboot command attempts contained shell path/line-break errors.
The first correctly formed `confirm` invocation reached the helper two seconds
after the deadline, when automatic rollback had already run. Its first
postboot health gate also incorrectly required `nix-daemon.service` itself to
be active. After a clean reboot this service may legitimately be
`inactive/dead` while the unchanged `nix-daemon.socket` is
`active/listening`; that is normal socket activation, not a failed Nix
runtime. The overly strict check caused a confusing early failure, but it did
not trigger, interrupt, or invalidate the already-completed rollback.

The helper now accepts either an active healthy daemon or a cleanly idle daemon
behind the exact active socket after reboot. Same-boot process-continuity gates
remain strict. A short `scripts/dgx-recovery` router also removes the fragile
root-owned snapshot path from normal operator commands. Neither helper exposes
a reboot action.

The journal line `FAIL|live canary payload does not match the exact candidate`
at the start of rollback is the transaction's expected predicate showing that
generation two was not already live. The immediately following activation,
profile selection, root synchronization, and final `PASS|rollback` records
prove the intended rollback path completed.

## Verified and cleaned host state

The snapshot-bound `verify-rolled-back` action passed protected-unit postboot
continuity, system health, GPU health, sanitized Tailscale/Tailscale SSH
health, exact generation-two state, and retained recovery evidence. Exact
cleanup then removed that evidence. Independent read-only observation at
`2026-09-02T21:45:02Z` found:

- classifier `ACTIVE_REGISTERED_GENERATION_TWO_TRIPLE_RETAINED`;
- `system-manager -> system-manager-2-link`;
- exact numbered links for generations one and two, with no generation-three
  numbered profile link;
- `system-manager-current ->` exact generation two;
- generation-one, generation-two, and generation-three direct pilot roots all
  pointing to their exact candidates;
- the declarative boot link absent;
- the recovery GC root, private recovery state, service link, timer link, and
  timer wants edge all absent;
- both recovery units `not-found/inactive/dead`;
- systemd `running` with zero failed units; and
- NVIDIA GB10 / driver 580.173.02 healthy.

There is no active recovery countdown. Generation three remains safely
retained by its direct pilot root and can be restored without rebuilding or
rebooting. The repository-pinned restoration path starts only from this exact
state, takes a new private snapshot, arms a transient ten-minute rollback to
generation two, repeats protected-service/GPU/Tailscale checks, requires local
console confirmation twice, preserves all three pilot roots, and performs no
reboot.

## Lessons and next boundary

The production recovery mechanism worked: the host booted, the persistent
timer survived reboot, and missing the confirmation deadline restored the
reviewed safe state automatically. The failed operator experience was command
ergonomics plus an overly strict Nix service check, not recovery failure.

Do not reuse snapshot `20260902T204546Z`; it is spent and cleaned. The next
host mutation is the separately guarded no-reboot restoration of generation
three. A later recovery snapshot and arming must use the new hash-pinned
helpers and a new timestamp. A later reboot still requires separate explicit
authorization.
