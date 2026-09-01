# System Manager first-registration host attempt 2 — 2026-09-01

This record documents the second invocation of the guarded live
first-generation registration wrapper on `sparkle-01`.

The result is **EXPECTED FAIL CLOSED BEFORE MUTATION**. Snapshot
`20260901T193734Z` was valid and bound to corrected repository commit
`0f03d01d46e9fbd340676d8c91d4f2697bd25ce4`, but the wrapper began at
`2026-09-01T20:14:40Z` when its recorded snapshot timestamp was 2,207 seconds
old. The maximum permitted age is 1,800 seconds.

## Exact refusal

```text
FAIL|snapshot is not in the current 30-minute registration window (age=2207s)
```

The age check is inside `assert_snapshot`. It runs before
`assert_unregistered_active_state`, before `systemd-run`, before
`registration_started=true`, and before the transaction's `apply-first`
operation. No rollback unit was created and no registration operation began.

Snapshot `20260901T193734Z` is retired and must not be reused or edited.

## Independent postflight

Read-only postflight at `2026-09-01T20:15:30Z` found:

- repository HEAD still
  `0f03d01d46e9fbd340676d8c91d4f2697bd25ce4` and the tree clean;
- host state `ACTIVE_RETAINED`;
- the dedicated profile directory, selected profile, generation-one link, and
  `system-manager-current` extra root all absent;
- both transient registration rollback units unloaded and inactive;
- all seven protected services active, unrestarted, loaded from their original
  fragments, and `NeedDaemonReload=no`;
- systemd `running` with zero failed units;
- NVIDIA GB10 on driver 580.173.02, P8, at 34°C; and
- sanitized Tailscale state backend `Running`, online,
  `WantRunning=true`, and `RunSSH=true`.

No registration, activation, deactivation, daemon reload, service operation,
boot linkage, pilot-root change, desktop switch, or Tailscale migration
occurred.

## Next gate

A later attempt requires another fresh root-owned snapshot, renewed
independent-console verification, and authorization bound to that exact new
snapshot. The refusal grants no authority to relax or bypass the 30-minute
limit.
