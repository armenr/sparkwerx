# System Manager first-registration host attempt 1 — 2026-09-01

This record documents the first invocation of the guarded live
first-generation registration wrapper on `sparkle-01`.

The result is **FAIL CLOSED BEFORE MUTATION**. The private snapshot passed its
integrity, age, candidate, transaction, pre-state, and clean-repository checks.
The following protected-service preflight then falsely reported that
`nix-daemon.service` had changed `MainPID`. The wrapper exited before it armed
the rollback timer or invoked the registration transaction. Independent
read-only postflight confirmed that the live canary remained
`ACTIVE_RETAINED`, the complete registration surface remained absent, and both
transient rollback units remained absent.

This was a wrapper-only parser defect. It was not a Nix daemon restart, a
System Manager failure, or a partial registration.

## Exact attempted inputs

| Field | Value |
| --- | --- |
| Host | `sparkle-01` |
| Candidate | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| Snapshot | `inventory/sparkle-01/raw/system-manager-registration/20260901T183009Z` |
| Repository commit in snapshot | `293547fb6424d25a5d5f4455f8593c0bb7d7c67a` |
| Transaction SHA-256 | `86c4be22ed350782920905897d80616b3949998d2662fd04ab9d1f5c3f4078a9` |
| Wrapper invocation | `2026-09-01T18:49:50Z` |
| Snapshot age at invocation | 1,163 seconds |
| Authorization | Explicitly bound to snapshot `20260901T183009Z` |
| Recovery | Independent local console available |

The snapshot was root-owned, mode 0700, checksum-valid, and recorded the exact
active-unregistered canary, exact pilot root, absent registration surface,
unchanged protected files, and protected-service process identities.

## Failure point and proof of no mutation

The wrapper completed `assert_snapshot`, entered
`assert_unregistered_active_state`, and stopped inside its first
`assert_protected_units` call:

```text
PASS|snapshot|...1163s old...
FAIL|nix-daemon.service changed MainPID
```

That call occurs before all three mutation milestones in the wrapper:

1. before `systemd-run` creates or arms
   `dgx-root-registration-rollback.timer`;
2. before `registration_started=true`; and
3. before the transaction executes `apply-first`.

The exit trap therefore had neither an armed timer nor a started registration
to report. Read-only postflight immediately after the refusal found:

- `ACTIVE_RETAINED`;
- `/nix/var/nix/profiles/system-manager-profiles` absent;
- `/nix/var/nix/profiles/system-manager-profiles/system-manager` absent;
- `/nix/var/nix/profiles/system-manager-profiles/system-manager-1-link`
  absent;
- `/nix/var/nix/gcroots/system-manager-current` absent; and
- both `dgx-root-registration-rollback.timer` and
  `dgx-root-registration-rollback.service` unloaded/inactive.

No registration, activation, deactivation, daemon reload, service operation,
boot linkage, pilot-root change, desktop switch, or Tailscale migration
occurred.

## Root cause

`snapshot-root-registration.sh` asks one `systemctl show` command for multiple
units and properties. The output consists of blank-line-delimited unit
records, but systemd does not promise to preserve the order of repeated `-p`
arguments. On this host, `MainPID` was emitted before `Id`.

The original `snapshot_property` parser streamed lines and began selecting only
after it encountered `Id=<wanted-unit>`. It therefore missed that unit's
earlier `MainPID` and continued into the next record. The value attributed to
`nix-daemon.service` was consequently the following unit's PID. Reproduction
showed parsed PID `2143` while the snapshot/current Nix daemon PID was `33487`.

The Nix daemon had actually been active continuously since
`2026-09-01 13:13:02 +04`, before the registration snapshot. Its
`NRestarts` was zero, result was `success`, fragment remained the factory
fragment, `NeedDaemonReload=no`, and there was no daemon journal event in the
snapshot-to-attempt window.

## Correction and regression checks

`snapshot_property` now parses each complete blank-line-delimited unit record,
matches its `Id`, and extracts the requested property independently of line
order. The transaction program itself was not changed.

The corrected wrapper passed:

- a synthetic regression with `MainPID` before `Id`;
- snapshot-versus-live comparisons of `FragmentPath`, `MainPID`, and
  `ActiveEnterTimestampMonotonic` for all seven protected units;
- `bash -n scripts/register-root-canary-pilot.sh`;
- `git diff --check`; and
- the repository's full `./scripts/check.sh`.

The correction leaves all three exact disposable derivations unchanged:

- activation:
  `/nix/store/jcrdk9p9lz3qiya2l1021339lsdvyxcg-container-test-dgx-root-canary.drv`;
- registration lifecycle:
  `/nix/store/m4zm42h6f8dch5mfm6aq6cpjp9jwzk90-container-test-dgx-root-canary-registration.drv`; and
- first-registration transaction:
  `/nix/store/lxnykcyvjn18pdv7y9rr1ryhvjgicazg-container-test-dgx-root-canary-registration-transaction.drv`.

The transaction SHA-256 remains
`86c4be22ed350782920905897d80616b3949998d2662fd04ab9d1f5c3f4078a9`,
and its recorded disposable result still matches the current transaction.

## Next gate

Snapshot `20260901T183009Z` is retired because it is bound to the repository
commit before this wrapper correction. It must never be reused or edited.

A retry requires the corrected repository to be committed and clean, followed
by a new root-owned snapshot, a repeated independent-console check, and new
explicit authorization bound to that exact fresh snapshot. The wrapper must
again arm its ten-minute registration-only rollback before `apply-first`, and
registration may be retained only after repeated automatic postflight and the
exact `KEEP REGISTRATION` confirmation.
