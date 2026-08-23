# Root-canary host preflight — 2026-08-24

This is durable evidence from a non-configuring inspection of `sparkle-01`. It
is not authorization to activate or register System Manager. The automatic
checks are current only for the observation window and must be rerun in the
activation maintenance window. The inspection was intended to be read-only; one
automatic stale-temporary-root cleanup by Nix is disclosed below.

| Field | Observed value |
| --- | --- |
| Observation window | `2026-08-23T21:48:16Z`–`2026-08-23T22:06:27Z` |
| Host | `sparkle-01` |
| Session transport | SSH |
| DGX OS | NVIDIA DGX Spark OTA 7.5.0 on Ubuntu 24.04 |
| Kernel | `6.17.0-1031-nvidia` |
| Candidate | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| Candidate validity | Valid in the local Nix store |
| Pre-activation assertion | PASS for Ubuntu |
| Matching disposable test | PASS; exact evidence still matches current derivation |
| Automatic host checks | PASS |
| Configuration/service changes | None |
| Nix bookkeeping exception | Three stale temporary-root records were automatically pruned by a root query |
| Host activation/registration | Not performed |
| Overall activation gate | **HOLD** |

## Exact candidate and prior test

The manifest evaluated to System Manager 1.1.0 at revision
`05e08c6dd739d7f3204e71322594bb8095334cfb`, using the reviewed private Nix
2.35.2 wrapper and `skip-empty-tmpfiles` patch. Its exact output is the candidate
shown above. The valid disposable-test output remains
`/nix/store/wn9dffp852vnvri1vcvz4mskmdgilnn0-container-test-dgx-root-canary`,
and `isolatedTest.matchesCurrent` remains true.

The candidate's `bin` directory contains `activate`, `deactivate`, `prepopulate`,
`register-profile`, the pre-activation assertion, and the manager engine. Its
other outputs are the reviewed `/etc` and service manifests. This pilot uses
low-level activation only. Registration remains a separate forbidden operation.

## Collision report

All paths below were absent. No parent directory, file, symlink, service, state,
profile, or GC root was created or changed while checking them.

| Exact path | State |
| --- | --- |
| `/etc/dgx-setup/canary` | Absent |
| `/etc/systemd/system/dgx-setup-canary.service` | Absent |
| `/etc/systemd/system/sysinit-reactivation.target` | Absent |
| `/etc/systemd/system/system-manager.target` | Absent |
| `/etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service` | Absent |
| `/var/lib/system-manager/state/system-manager-state.json` | Absent |
| `/nix/var/nix/profiles/system-manager-profiles/system-manager` | Absent |
| `/nix/var/nix/gcroots/system-manager-current` | Absent |
| `/nix/var/nix/gcroots/dgx-setup-root-canary-pilot` | Absent |
| `/etc/profile.d/system-manager-path.sh` | Absent |
| `/etc/environment.d/10-system-manager.conf` | Absent |
| `/etc/systemd/system/default.target.wants/system-manager.target` | Absent |
| `/etc/systemd/system/system-manager-path.service` | Absent |
| `/etc/systemd/system/userborn.service` | Absent |
| `/run/wrappers` | Absent |
| `/run/current-system` | Absent |

The generated `/etc` manifest has `replaceExisting=false`. Its systemd source
contains exactly the three reviewed units and the single target-wants symlink;
the canary service only tests that `/etc/dgx-setup/canary` is a symlink.

## Disclosed Nix bookkeeping side effect

An evidence-gathering `nix-store --query --roots` call was intended only to
determine whether the exact candidate was retained. Nix 2.35.2 also used that
query to prune three stale temporary-root files for exited process IDs under
`/nix/var/nix/temproots` (`597438`, `594080`, and `635923`). The command returned
no live GC root for the candidate. It did not delete a store object, create or
remove a live root, alter configuration, reload systemd, or change a service.

This cleanup was Nix's automatic stale-bookkeeping behavior, not a manual
deletion, but it was still a host-side mutation and is recorded here explicitly.
Do not rerun `--query --roots` as part of the ordinary preflight; the reusable
helper uses only exact store-path validity checks.

## Live health report

Systemd reported the machine state as `running` with no failed units. The
following protected services were active and had `NeedDaemonReload=no`:

- `nix-daemon.service`
- `tailscaled.service`
- `gdm.service`
- `docker.service`
- `dgx-dashboard.service`
- `dgx-dashboard-admin.service`
- `nvidia-persistenced.service`

The NVIDIA query succeeded for the GB10 GPU and driver 580.173.02. Tailscale
1.102.3 reported only the sanitized approved fields: backend `Running`, self
online, `WantRunning=true`, and `RunSSH=true`. No node identity, address,
tailnet, auth material, or raw preferences were recorded.

## Recovery gate

The host has an active graphical `seat0`, but the inspection session itself is
SSH. An active GDM seat is evidence that a local session exists; it does not
prove that Armen can recover the machine independently if Tailscale, networking,
or the activation session fails.

Before any activation, Armen must confirm that he is at the machine or has
tested independent console/recovery access during the same maintenance window.
This is intentionally a human gate and cannot be marked PASS by the automatic
preflight helper.

## Same-window snapshot

Run the read-only automatic preflight again first:

```bash
./scripts/preflight-root-canary.sh
```

After the console gate passes, create a private root-owned snapshot immediately
before arming rollback. Replace only the timestamp; keep the exact candidate:

```bash
snapshot_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
snapshot_dir="$PWD/inventory/sparkle-01/raw/system-manager-canary/$snapshot_stamp"

sudo ./scripts/snapshot-root-canary.sh \
  /nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager \
  "$snapshot_dir"
```

The destination is already excluded by `inventory/**/raw/`. The helper refuses
an existing destination or any collision, archives the current 296 KiB
`/etc/systemd/system` tree with ownership/ACL/xattr metadata, records the exact
guarded paths as absent, hashes the four protected account/Nix files without
copying their contents, records sanitized service state, and writes checksums.
It makes no configuration or service change. Treat the archive as private host
configuration and do not commit or upload it.

## Exact store-retention gate

Inspection of the pinned System Manager 1.1.0 source proved that low-level
`activate` writes state and applies files/services but does not create a profile
or GC root. The separate `register-profile` command creates both upstream
registration paths; it remains untested here and is not authorized. The exact
candidate currently has store referrers from the disposable test, but no
registered root, so those referrers are not a durable retention guarantee.

Nix 2.35.2 treats a symlink under `/nix/var/nix/gcroots` to a store path as a
direct garbage-collector root. The repository therefore declares one narrow
pilot-only path:

```text
/nix/var/nix/gcroots/dgx-setup-root-canary-pilot
```

Creating it is a host mutation and was not performed. After the snapshot and
explicit authorization for the live pilot, create and verify only this exact
root before arming rollback:

```bash
sudo ln -s -- \
  /nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager \
  /nix/var/nix/gcroots/dgx-setup-root-canary-pilot

readlink -- /nix/var/nix/gcroots/dgx-setup-root-canary-pilot
```

The observed target must exactly equal the candidate path. This deterministic
direct root avoids a floating flake reference and avoids pretending that
upstream generation registration occurred. It is not a long-term substitute
for registration. It must remain while the canary is active and until rollback
or manual deactivation has been verified. Never make its removal part of the
rollback timer; if deactivation has a problem, the closure and repair tools must
remain available. Cleanup requires a separate exact check and authorization.

The retention behavior follows the
[Nix 2.35.2 garbage-collector-root definition](https://nix.dev/manual/nix/2.35/package-management/garbage-collector-roots).

## Exact timed rollback plan

The rollback guard is a transient systemd timer. Creating it is a host mutation,
so these commands are prepared but were not run during this preflight. After the
snapshot, explicit activation authorization, and exact pilot-root verification,
arm it before activation:

```bash
sudo systemd-run \
  --unit=dgx-root-canary-rollback \
  --description="Timed rollback for DGX System Manager canary" \
  --collect \
  --service-type=exec \
  --on-active=10m \
  --timer-property=AccuracySec=1s \
  /nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager/bin/deactivate

systemctl show dgx-root-canary-rollback.timer \
  -p ActiveState -p SubState -p NextElapseUSecMonotonic --no-pager
```

Only after the timer is visibly armed may the separately authorized activation
use this exact command:

```bash
sudo /nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager/bin/activate
```

If SSH or health verification fails, do nothing and let the ten-minute timer run
the exact deactivation program. From the independent console, rollback can also
be triggered immediately with that same `bin/deactivate` path.

After activation, verify the five exact managed paths, canary unit, protected
file hashes, Tailscale/Tailscale SSH, GDM, Docker, Nix, DGX/NVIDIA services, and
GPU query. Disarm the timer only after all checks pass from both the activation
session and the independent recovery path:

```bash
sudo systemctl stop dgx-root-canary-rollback.timer
```

Because `--collect` is used, the transient units are unloaded after they become
inactive. Keep the pilot GC root for as long as the canary remains active. Do not
register a profile. Deactivation intentionally leaves an empty System Manager
state file; removing that file or the pilot GC root is a separate cleanup
decision, not part of emergency rollback.

## Remaining gates

1. Confirm independent local console/recovery access in the maintenance window.
2. Rerun the automatic preflight and create the private same-window snapshot.
3. Obtain Armen's explicit authorization for this one host activation.
4. Create and verify the exact manifest-declared pilot GC root.
5. Arm and verify the exact transient rollback timer.

Until all five occur, the correct state is **HOLD** and no activation command is
authorized.
