# Root-canary container validation — 2026-08-24

This is the durable result record for the separately authorized disposable
System Manager activation/deactivation test. It is validation evidence for the
exact derivation below, not authorization to activate or register System
Manager on the DGX host.

| Field | Observed value |
| --- | --- |
| Command | `sudo ./scripts/test-root-canary.sh` |
| Result | **PASS** (exit 0) |
| Test derivation | `/nix/store/jcrdk9p9lz3qiya2l1021339lsdvyxcg-container-test-dgx-root-canary.drv` |
| Valid output | `/nix/store/wn9dffp852vnvri1vcvz4mskmdgilnn0-container-test-dgx-root-canary` |
| Activation timestamp in log | `2026-08-23T21:10:59Z` |
| Host activation | **Not performed** |
| Host postflight | **Clean** |

The local build log proves that the Ubuntu 24.04 ARM64 container booted; the
patched System Manager reported `No managed tmpfiles configuration; skipping
systemd-tmpfiles`; activation managed exactly the five allowlisted paths and
three allowlisted service keys; and the unmanaged tmpfiles sentinel remained
absent before, during, and after activation/deactivation. The hashes of the
container's `/etc/nix/nix.conf`, `/etc/passwd`, `/etc/group`, and `/etc/shadow`
were unchanged. No generation profile or GC root was registered. Deactivation
removed all five managed paths and left the expected empty version-0 state
record inside the disposable container, which then shut down normally.

Read-only postflight on the DGX host found all five canary paths, the manager
state file, the generation profile, and the GC root absent. `nix-daemon`,
`tailscaled`, and `gdm` were active and each reported `NeedDaemonReload=no`.

The top-level Nix 2.35.2 process emitted:

```text
warning: Ignoring setting 'auto-allocate-uids' because experimental feature 'auto-allocate-uids' is not enabled
```

This warning did not appear in the successful derivation log and did not change
the test result. The direct local-store build demonstrably had the required UID
range and cgroup capability because the container test ran to completion. Keep
the explicit `auto-allocate-uids` and `cgroups` feature flags, and keep
`NIX_USER_CONF_FILES=/dev/null` as the root-user configuration isolation
boundary. Do not claim that the latter suppresses this observed top-level
warning.

The flake manifest records both these observed store paths and the paths for the
currently evaluated test. Its `isolatedTest.matchesCurrent` field must be true.
Any input, patch, test, or derivation change makes this evidence stale and
requires a newly authorized disposable test before a host pilot can be
considered.
