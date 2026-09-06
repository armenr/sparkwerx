# System Manager first-registration transaction container test — 2026-09-01

## Verdict

**PASS for the exact disposable derivation. The live host remains
`ACTIVE_RETAINED`, unregistered, and not boot-linked.**

The separately authorized helper exercised the guarded transaction only inside
an Ubuntu 24.04.4 `systemd-nspawn` container. Nix realized the exact expected
output, its store hash verifies, its deriver is exact, and the build log shows
all nine named subtests completed. Independent read-only host postflight found
no root-manager drift and no protected-service, system, GPU, or sanitized
Tailscale regression.

This pass validates the tested first-generation transaction and exact
rollback. It does not authorize live host registration, activation, boot
linkage, Tailscale migration, desktop switching, or removal of the pilot root.

## Exact evidence

| Field | Value |
| --- | --- |
| Repository commit used by the test | `458d1e640f89a7986b1a33b6ca41741d597096da` |
| Read-only verification time | `2026-09-01T15:04:47Z` |
| Helper | `sudo ./scripts/test-root-registration-transaction.sh` |
| Exact candidate | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| Transaction SHA-256 | `86c4be22ed350782920905897d80616b3949998d2662fd04ab9d1f5c3f4078a9` |
| Test derivation | `/nix/store/lxnykcyvjn18pdv7y9rr1ryhvjgicazg-container-test-dgx-root-canary-registration-transaction.drv` |
| Test output | `/nix/store/mrslm372127pgwbfv3r7kprj2igxpki2-container-test-dgx-root-canary-registration-transaction` |
| Output hash | `sha256:1smdvp76zf0hz5cxzjjghf8c2z4hjkvbkwf4ikmgpf2cz8fv4ram` |
| Prior lifecycle derivation | `/nix/store/m4zm42h6f8dch5mfm6aq6cpjp9jwzk90-container-test-dgx-root-canary-registration.drv` |
| Original activation derivation | `/nix/store/jcrdk9p9lz3qiya2l1021339lsdvyxcg-container-test-dgx-root-canary.drv` |
| Private test Nix | 2.35.2 |
| Required host state before execution | `ACTIVE_RETAINED` |
| Host state after the build | `ACTIVE_RETAINED` |
| Host registration performed | No |
| Host activation performed by this test | No |
| Host postflight | Clean |

The output exists, `nix-store --verify-path` succeeds, and
`nix-store --query --deriver` resolves it to the exact derivation above. The
current flake still evaluates to that derivation and output. The prior lifecycle
and original activation derivations are unchanged. A valid output and its
`passed` marker are produced only after the test driver exits successfully.

## Passed transaction assertions

All nine named subtests completed:

1. an active retained canary began exactly unregistered;
2. a preflight collision at the upstream extra GC root caused no profile
   mutation;
3. an injected post-preflight collision reproduced upstream's partial profile
   advancement, after which the wrapper removed only its exact links and
   preserved the foreign collision;
4. an injected failure after complete registration restored both registration
   surfaces to absence;
5. a missing exact pilot root refused registration;
6. rollback refused unknown profile content and did not delete it;
7. successful first-generation registration created only the expected profile
   links and direct extra root without changing live activation;
8. exact rollback was idempotent and restored the active-unregistered state;
   and
9. disposable cleanup removed the canary and pilot fixture and left only expected
   empty version-0 manager state.

Throughout the test, the container's `/etc/nix/nix.conf`, `/etc/passwd`,
`/etc/group`, and `/etc/shadow` hashes remained unchanged. The unmanaged
tmpfiles sentinel was never processed. Boot linkage, global PATH hooks,
`userborn`, wrappers, `/run/current-system`, and every other forbidden path
remained absent. Failure injection was accepted only because the test ran
inside a systemd-nspawn container.

## Independent host postflight

The repository classifier returned `ACTIVE_RETAINED`, matching the
[attempt-3 live-state authority](2026-09-01-host-canary-attempt-3.md).
Therefore:

- the exact five managed host paths and three service keys still match the
  retained candidate;
- `/nix/var/nix/profiles/system-manager-profiles` remains absent;
- `/nix/var/nix/gcroots/system-manager-current` remains absent;
- the direct pilot root still retains the exact candidate;
- the boot link and all broader root-manager paths remain absent; and
- `dgx-root-registration-rollback.timer` and its service are not loaded.

All seven protected services were active with `NeedDaemonReload=no`:

- `nix-daemon.service`;
- `tailscaled.service`;
- `gdm.service`;
- `docker.service`;
- `dgx-dashboard.service`;
- `dgx-dashboard-admin.service`; and
- `nvidia-persistenced.service`.

Systemd reported `running` with zero failed units. The GPU reported NVIDIA
GB10, driver 580.173.02, P8, and 34°C. Sanitized Tailscale state was backend
`Running`, online, `WantRunning=true`, and `RunSSH=true`. No raw Tailscale
identity, address, node, or tailnet data was retained.

## Operational residue

The successful build deliberately retains test paths and build records in the
Nix store. Root-local UID allocation and cgroup execution may also retain Nix
bookkeeping under `/nix/var/nix/userpool2` and `/nix/var/nix/cgroups`.
These are not System Manager profiles or host registration. Do not delete them
casually.

## Consequence for the live gate

The tested transaction may now enter a separately authorized live-registration
gate. Before any live invocation, require a clean committed tree, exact
derivation/checksum matches, a fresh root-owned snapshot no older than 30
minutes, independent console access, unchanged protected service processes,
the exact ten-minute registration-only rollback, and authorization bound to
that snapshot.

The live wrapper must preserve the active canary and pilot root, create no boot
link, perform no activation/deactivation or service operation, repeat all
postflight checks, and require exactly `KEEP REGISTRATION` before disarming
rollback. This evidence alone grants none of that live authority.
