# Tailscale guarded migration lifecycle — 2026-09-05

## Result

PASS. The exact generation-three to generation-four transaction, persistent
rollback bundle, reboot behavior, and vendor-unit restoration completed inside
the disposable Ubuntu systemd-nspawn test. The root-only wrapper also proved
that the real host remained on generation three with the same running apt-owned
Tailscale process before and after the test.

```text
PASS|tailscale_unit_lifecycle|container handoff/reboot/rollback passed; live host stayed exact
```

## Exact passed outputs

| Artifact | Store path |
| --- | --- |
| Production generation-four candidate | `/nix/store/vjw778sf95r42a1zbivlk8z4p45y7qhx-system-manager` |
| Production candidate derivation | `/nix/store/cdwy32afchjq31dcz0wyw4d7dxb3blf8-system-manager.drv` |
| Production rollback bundle | `/nix/store/cwzdq5h7j5751dq58znbgwpxylllb209-dgx-tailscale-migration` |
| Rollback-bundle derivation | `/nix/store/552pydy0bklxghajxs5ika29dvl1hcmr-dgx-tailscale-migration.drv` |
| Disposable lifecycle result | `/nix/store/x3y50k9796jkcsbp2pyrc947yyqp741r-container-test-dgx-tailscale-unit-lifecycle` |
| Disposable lifecycle derivation | `/nix/store/p0qnjscz9zr62mxaylwqy3gfizhc6id4-container-test-dgx-tailscale-unit-lifecycle.drv` |
| Pinned Tailscale package | `/nix/store/cr8z0ckc23p6kxvsyn9wfslqb5sj3m5p-tailscale-1.102.3` |
| Exact migration transaction | `/nix/store/mncwzaj1d39xj2di3jk22n7fs9ppaf4x-root-tailscale-migration-transaction.sh` |

The flake policy check and Nix-native ShellCheck gate also passed. The operator
itself is not part of the container mutation path; it is linted and is required
to rerun the exact lifecycle result before it may arm a live migration.

## Proven lifecycle

The container test uses fake apt and Nix daemons and a non-secret identity
marker. It proves all of the following without contacting a tailnet:

1. Generation three leaves the running vendor unit and daemon untouched.
2. An injected failure immediately after generation-four registration restores
   the exact generation-three profile and vendor access plane.
3. Generation four registers and activates, takes unit ownership, and performs
   exactly one deliberate daemon restart while preserving mutable identity.
4. The Nix-owned unit and identity survive a reboot.
5. Explicit rollback removes only generation-four ownership, restores the
   still-installed vendor unit, and survives another reboot.
6. An enabled persistent timer survives a candidate reboot and automatically
   restores generation three plus the vendor unit when confirmation is absent.

The host wrapper checks the live System Manager generation, apt unit fragment,
boot link, daemon PID/start time, active state, and pending-reload state on both
sides of the disposable test.

## Live boundary

This PASS did not activate generation four on `sparkle-01`. The live migration
must go through `scripts/dgx-tailscale`: it requires a clean exact commit,
rechecks apt/Nix binary equality and sanitized Tailscale health, creates a
private snapshot, arms the persistent rollback before mutation, and launches
the restart in a detached systemd worker. Confirmation is intentionally
unavailable until generation four has survived one separately authorized real
reboot and a fresh Tailscale connection. The apt package remains installed as
the rollback source.
