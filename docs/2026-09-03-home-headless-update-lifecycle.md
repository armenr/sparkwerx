# Guarded headless Home generation-update lifecycle

Date: 2026-09-03 UTC

Host scope: `n0b0dy@sparkle-01`

Result: repository design implemented; disposable completed and partial-update
rollback passed; live profile unchanged

## Operator interface

Later package or lock-file changes use the same short operator as first
activation:

```bash
./scripts/dgx-home update-headless
```

The command needs no sudo and no typed confirmation phrase. If the evaluated
candidate already equals the live generation, it exits successfully without a
snapshot, timer, profile generation, or other mutation.

When a reviewed commit evaluates a distinct candidate, the command:

1. proves the live generation still matches the committed deployment record;
2. builds the exact Home, package-policy, Codex, and Devbox checks;
3. verifies the frozen System Manager lane, protected services, Tailscale, the
   zero-user-systemd headless boundary, and a non-mutating activation dry run;
4. snapshots the prior Home/user-profile symlink inventories and mutable Codex
   config under ignored `inventory/<host>/private/` state;
5. retains the new candidate and its precomputed one-package user environment;
6. arms a ten-minute user rollback before invoking Home Manager;
7. activates and verifies the exact next numbered Home and user-profile
   generations twice; and
8. automatically disarms rollback after both postflights pass.

The previous numbered generation remains available after a successful update.
The command never uses sudo, changes a root role, restarts a protected service,
switches a desktop, migrates Tailscale, or reboots.

## Rollback model

The timer and manual `rollback-update <snapshot-stamp>` action accept the
known old state, the known new state, or a partial transition between them.
They refuse foreign files, generation links, GC roots, or managed-link targets.
Rollback atomically reselects the exact prior Home and user-profile links,
restores the three managed home links, restores Codex policy bytes only when
the file was not independently edited, and removes only the exact failed new
generation links. Older history is untouched.

The snapshot holds an exact direct root for the candidate and a precomputed
user environment so its ten-minute rollback cannot race garbage collection.
Snapshot checksums bind the transaction program, context, prior inventories,
Codex baseline, and protected-service identities.

## Disposable evidence

`scripts/test-dgx-home-update-rollback.sh` builds an inert second candidate
whose only difference is a test session-variable payload. In a private
temporary home it tests both a completed generation-one to generation-two
transition and an interruption after Home Manager's write boundary, then
invokes the actual rollback implementation and proves exact restoration of:

- both selected profile links and their generation-one targets;
- the Home current-generation GC root;
- all three managed home links;
- the mutable Codex config baseline; and
- the pre-update profile/GC-root inventories.

The test leaves the real Home profile untouched. A live update was neither
needed nor attempted because the repository candidate still equals retained
generation one.

## Deployment-record rule

A dependency-update commit may intentionally make `currentCandidate` differ
from `observedCandidate`; flake evaluation no longer blocks that reviewable
state. The update audit reports `UPDATE_AVAILABLE` only when the live profile
still exactly matches the retained deployment evidence. After a real update,
record the new observed candidate, user environment, Home files, generation,
and retained snapshot in a follow-up clean commit before performing another
Home update.
