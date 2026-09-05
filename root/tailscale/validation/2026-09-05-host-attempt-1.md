# Tailscale migration host attempt 1 — automatic rollback and cleanup

## Outcome

SAFE ROLLBACK. Snapshot `20260905T073046Z` had an elapsed persistent rollback
timer and a verified `rolled-back` marker when this session resumed the live
migration. A new `migrate` invocation failed closed before mutation because the
old guard directory still existed.

The guarded status check then proved:

```text
PASS|generation_three|exact boot-persistent generation three and vendor Tailscale are active
PASS|tailscale|backend=Running;online=true;WantRunning=true;RunSSH=true;identity=unchanged
PASS|health|systemd=running;failed_units=0;gpu=NVIDIA GB10, 580.173.02, P8, 37
PASS|protected_units|five factory services remain active and unrestarted
MIGRATION_STATUS=ROLLED_BACK_CLEANUP_PENDING
```

`scripts/dgx-tailscale cleanup-rolled-back` revalidated the same state, removed
the spent timer, rollback service links, rollback-bundle root, markers, and
private live context, then recorded `ROLLED_BACK` in the private snapshot. It
did not reboot or alter the exact live generation-three/vendor state. The exact
generation-four candidate root was intentionally retained.

## Retry correction

Two operator issues were identified without compromising the host:

1. Rootless `plan` checked the private `context` file, which an unprivileged
   process cannot see through the mode-0700 state directory. It therefore
   incorrectly reported no guard. It now checks the visible guard directory and
   unit/root surface without reading private contents.
2. The cleanup intentionally retained the exact generation-four GC root, but
   the next migration treated any such root as a collision. Retry now permits
   and reuses only the exact evaluated candidate symlink; a different target or
   non-symlink still fails closed.

This record does not authorize deleting the private snapshot, removing any
System Manager generation, or bypassing the next migration's complete preflight
and lifecycle rerun.
