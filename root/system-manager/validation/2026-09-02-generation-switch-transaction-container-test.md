# System Manager generation-switch transaction container test — 2026-09-02

## Verdict

**PASS for the exact disposable derivation. The live host remains
`ACTIVE_REGISTERED_RETAINED` on generation one, with no generation-two host
retention root and no boot link.**

The separately authorized helper exercised the guarded generation switch and
rollback only inside an Ubuntu 24.04.4 `systemd-nspawn` container. Nix realized
the exact expected output, its store hash verifies, its deriver is exact, and
the build log shows all eleven named subtests completed. Independent read-only
host postflight found no root-manager drift and no protected-service, system,
GPU, or sanitized Tailscale regression.

This pass validates the tested two-generation transaction and exact rollback.
It permits repository design of a separate live snapshot/timed-rollback/local-
console wrapper. It does not authorize creating the generation-two host pilot
root, switching the live profile, activating generation two, changing boot
linkage, rebooting, migrating Tailscale, switching desktops, or removing either
current generation-one root.

## Exact evidence

| Field | Value |
| --- | --- |
| Repository commit used by the test | `8b15fdf3e551c07a9a6bed54685109e3f2c005e9` |
| Read-only verification time | `2026-09-02T07:02:25Z` |
| Helper | `sudo ./scripts/test-root-generation-switch-transaction.sh` |
| Helper exit status | `0` |
| Generation one | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| Generation two | `/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager` |
| Transaction SHA-256 | `ea1a6ddc509eef4ac80aa165e29a6612d1f1b59b93681cdf813ee8b1ff6d8cdd` |
| Test derivation | `/nix/store/0llhzgyraq4gr7m4agbv8wbvs7xdcql2-container-test-dgx-root-canary-generation-switch-transaction.drv` |
| Test output | `/nix/store/l5s5m3q4bd338jflq1abycajwxrfbj5v-container-test-dgx-root-canary-generation-switch-transaction` |
| Output hash | `sha256:01zxs9x67jgp5ifskcvkr8lihddw886ysqcqgaaw3v6dr9f18766` |
| Prior first-registration transaction derivation | `/nix/store/lxnykcyvjn18pdv7y9rr1ryhvjgicazg-container-test-dgx-root-canary-registration-transaction.drv` |
| Prior registration lifecycle derivation | `/nix/store/m4zm42h6f8dch5mfm6aq6cpjp9jwzk90-container-test-dgx-root-canary-registration.drv` |
| Original activation derivation | `/nix/store/jcrdk9p9lz3qiya2l1021339lsdvyxcg-container-test-dgx-root-canary.drv` |
| Private test Nix | 2.35.2 |
| Required host state before execution | `ACTIVE_REGISTERED_RETAINED` |
| Host state after the build | `ACTIVE_REGISTERED_RETAINED` |
| Host generation-two retention root after the build | Absent |
| Host registration/profile switch performed | No |
| Host activation performed by this test | No |
| Host candidate retention performed | No |
| Host postflight | Clean |

The output exists, `nix-store --verify-path` succeeds, and
`nix-store --query --deriver` resolves it to the exact derivation above. The
current flake still evaluates to that derivation and output. The original
activation, registration-lifecycle, and first-registration transaction
derivations are unchanged. A valid output is produced only after the test driver
exits successfully.

## Passed transaction assertions

All eleven named subtests completed:

1. registered generation one refused an unretained generation-two candidate;
2. the exact generation-one switch pre-state verified;
3. unknown profile content refused switching without mutation;
4. an injected upstream extra-root collision exposed partial profile
   advancement, restored generation one, and preserved the foreign collision;
5. an injected failure after complete generation-two registration restored
   exact generation one;
6. an injected failure after generation-two activation restored exact
   generation one;
7. a successful switch selected, rooted, and activated only exact generation
   two;
8. duplicate apply refused and preserved exact generation two;
9. rollback refused a foreign extra root before changing live container state;
10. exact rollback was idempotent and restored registered/live generation one;
    and
11. disposable cleanup removed registration and both pilot fixtures, deactivated
    the canary, and left exact empty version-0 manager state.

Throughout the test, the container's `/etc/nix/nix.conf`, `/etc/passwd`,
`/etc/group`, and `/etc/shadow` hashes remained unchanged. The unmanaged
tmpfiles sentinel was never processed. Boot linkage, global PATH hooks,
`userborn`, wrappers, `/run/current-system`, and every other forbidden path
remained absent. Both candidate roots were preserved during transaction and
rollback. Failure injection was accepted only because the test ran inside a
systemd-nspawn container.

## Independent host postflight

The repository classifier returned `ACTIVE_REGISTERED_RETAINED`, matching the
[retained generation-one authority](2026-09-01-first-registration-host-attempt-3.md).
Therefore the exact selected profile, generation-one link, upstream extra root,
pilot root, five managed paths, and three service keys still resolve to
generation one. The generation-two pilot root remains absent, the boot link and
all broader root-manager paths remain absent, and the disposable helper made no
host registration, activation, profile switch, candidate-retention, daemon-
reload, service, or boot-link change.

All seven protected services were active with `NeedDaemonReload=no`:

- `nix-daemon.service`;
- `tailscaled.service`;
- `gdm.service`;
- `docker.service`;
- `dgx-dashboard.service`;
- `dgx-dashboard-admin.service`; and
- `nvidia-persistenced.service`.

Systemd reported `running` with zero failed units. The GPU reported NVIDIA GB10,
driver 580.173.02, P8, and 36°C. Sanitized Tailscale state was backend
`Running`, online, `WantRunning=true`, and `RunSSH=true`. No raw Tailscale
identity, address, node, or tailnet data was retained.

## Warning and operational residue

The top-level root Nix invocation emitted the already documented non-fatal
warning that `auto-allocate-uids` was ignored because the feature was not
enabled at that client layer. The helper used direct `--store local` execution
with process-local `auto-allocate-uids` and `cgroups`; the derivation completed,
the successful build log contains the eleven finished subtests, and the valid
output is the test verdict. No daemon configuration was persisted or restarted.

The build deliberately retains test paths and build records in the Nix store.
Root-local UID allocation and cgroup execution may also retain Nix bookkeeping
under `/nix/var/nix/userpool2` and `/nix/var/nix/cgroups`. These are not System
Manager profiles or host registration. Do not delete them casually.

## Consequence for the live gate

The exact transaction may now enter repository design for a separately guarded
live switch wrapper. Before any live invocation, require a clean committed tree,
the exact tested candidates/transaction/derivation, a fresh private root-owned
snapshot, independent console access, a generation-two pilot root created only
inside that separately authorized window, unchanged protected-service
processes, an exact ten-minute rollback to registered/live generation one,
repeated GPU/Tailscale/system postflight, and authorization bound to that fresh
snapshot.

This evidence grants no live-switch authority. Stop before creating the
generation-two host root or running the transaction on `sparkle-01`.
