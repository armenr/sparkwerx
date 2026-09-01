# System Manager registration lifecycle container test — 2026-09-01

## Verdict

**PASS for the exact disposable derivation. The live host remains
`ACTIVE_RETAINED`, unregistered, and not boot-linked.**

The separately authorized helper ran the lifecycle only inside an Ubuntu
24.04.4 `systemd-nspawn` container. Nix realized the exact expected output,
its store hash verifies, and the build log shows every subtest completed.
Independent read-only host postflight found no root-manager drift and no
protected-service regression.

This pass validates the tested registration semantics. It does not authorize
`register-profile` on the host, live activation, boot linkage, Tailscale
migration, desktop switching, or removal of the pilot retention root.

## Exact evidence

| Field | Value |
| --- | --- |
| Repository commit used by the test | `759997de70c92147204c120c900f03fca488f859` |
| Read-only verification time | `2026-09-01T12:54:16Z` |
| Helper | `sudo ./scripts/test-root-registration.sh` |
| Baseline generation | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| Disposable generation two | `/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager` |
| Test derivation | `/nix/store/m4zm42h6f8dch5mfm6aq6cpjp9jwzk90-container-test-dgx-root-canary-registration.drv` |
| Test output | `/nix/store/jkl1lsqnvmv5iznk7q70xjk9l6xfvf6j-container-test-dgx-root-canary-registration` |
| Output hash | `sha256:0jkwb59zdilvdaadw826wfa6vkjmsj0agd58ns16gywsny1yf2mv` |
| Private test Nix | 2.35.2 |
| Host state immediately before authorization | `ACTIVE_RETAINED` |
| Host state after the build | `ACTIVE_RETAINED` |
| Host registration performed | No |
| Host activation performed by this test | No |
| Host postflight | Clean |

The output exists, `nix-store --verify-path` succeeds, `nix path-info`
recognizes it, and `nix-store --query --deriver` resolves it back to the exact
derivation above. A valid test output is created only after the test driver
exits successfully.

## Passed lifecycle assertions

All nine named subtests completed:

1. a forced regular-file collision at `system-manager-current` made
   `register-profile` fail after the disposable Nix profile had advanced,
   proving the operation is non-transactional;
2. only that disposable partial-registration fixture was reset;
3. generation one registered without activating files or services;
4. generation one activated within the exact five-path/three-service boundary;
5. generation two registered while generation one remained live;
6. generation two became live only after explicit activation;
7. selecting profile generation one changed neither the live generation-two
   marker nor the extra GC root;
8. re-registering generation one synchronized the extra root before explicit
   rollback activation; and
9. deactivation removed the managed surface and left exact empty version-0
   state while disposable registration history and its extra root remained.

Throughout the test, the container's `/etc/nix/nix.conf`, `/etc/passwd`,
`/etc/group`, and `/etc/shadow` hashes remained unchanged. The unmanaged
tmpfiles sentinel was never processed. Boot linkage, global PATH hooks,
`userborn`, wrappers, `/run/current-system`, and every other forbidden path
remained absent.

## Independent host postflight

The repository classifier returned `ACTIVE_RETAINED`, matching the
[attempt-3 live-state authority](2026-09-01-host-canary-attempt-3.md).
Therefore:

- the exact five managed host paths and three service keys still match the
  retained baseline candidate;
- both upstream host registration paths and every numbered generation link
  remain absent;
- the direct pilot root still points to the exact baseline candidate;
- the boot link and all broader root-manager paths remain absent; and
- the transient rollback units remain unloaded.

All seven protected services were active with `NeedDaemonReload=no`:

- `nix-daemon.service`;
- `tailscaled.service`;
- `gdm.service`;
- `docker.service`;
- `dgx-dashboard.service`;
- `dgx-dashboard-admin.service`; and
- `nvidia-persistenced.service`.

Systemd reported `running` with zero failed units. The GPU reported NVIDIA
GB10, driver 580.173.02, P8, and 36°C. Sanitized Tailscale state was backend
`Running`, online, `WantRunning=true`, and `RunSSH=true`. No raw
Tailscale identity, address, node, or tailnet data was retained.

## Operational residue

The successful build deliberately retains test paths and build records in the
Nix store. Root-local UID allocation and cgroup execution may also retain Nix
bookkeeping under `/nix/var/nix/userpool2` and
`/nix/var/nix/cgroups`. These are not System Manager profiles or host
registration. Do not delete them casually.

## Consequence for the next design

A live fleet wrapper must treat these as three separate checked state
transitions:

1. select or create the intended Nix profile generation;
2. synchronize the separate `system-manager-current` GC root; and
3. explicitly activate the selected generation.

Rollback must restore those same three states deliberately. A failed
`register-profile` cannot be assumed to leave the profile untouched, and
deactivation cannot be assumed to remove registration history. The next step is
a reviewed live-registration transaction and rollback design—not live
registration itself.
