# System Manager host canary attempt 2 — 2026-08-24

This record documents the second live activation of the exact System
Manager canary on `sparkle-01`. The corrected helper passed its full automatic
activation and post-activation checks. The required `KEEP CANARY` confirmation
was not entered because Enter was pressed accidentally, so the helper failed
closed and deliberately left the ten-minute rollback armed. Exact timed
deactivation then completed successfully.

The result is **PASS for the corrected automatic activation boundary and timed
rollback**, but **not a retained host activation**. System Manager is inactive
and unregistered.

## Exact inputs

| Field | Value |
| --- | --- |
| Host | `sparkle-01` |
| Candidate | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| Candidate revision | `05e08c6dd739d7f3204e71322594bb8095334cfb` |
| Private Nix | 2.35.2 |
| Activation helper commit | `cd2e8e5` |
| Snapshot | `inventory/sparkle-01/raw/system-manager-canary/20260824T070443Z` |
| Disposable test derivation | `/nix/store/jcrdk9p9lz3qiya2l1021339lsdvyxcg-container-test-dgx-root-canary.drv` |
| Disposable test result | PASS; matched the exact candidate |
| Authorization | Explicit approval for this host canary only |
| Recovery gate | User reported physical console access; the retention confirmation was not completed |

The private snapshot was root-owned, mode 0700, checksum-valid, 138 seconds old,
and bound to the exact candidate. It recorded the prior empty version-0 state
and the existing direct pilot root pointing to the candidate. All five managed
paths, both upstream registration paths, and every forbidden path were absent
before activation.

## Activation timeline

- `2026-08-24T07:07:28Z`: the helper validated the fresh snapshot, prior state,
  exact retained root, protected services, system health, GPU, sanitized
  Tailscale state, and collision boundary.
- It armed `dgx-root-canary-rollback.timer` for ten minutes, with its transient
  service bound to the exact candidate's `bin/deactivate` program.
- Low-level activation completed and wrote the exact version-1 state.
- `2026-08-24T07:07:29Z`: corrected automatic postflight passed.
- The confirmation prompt received an empty line instead of exactly
  `KEEP CANARY`. The helper exited and correctly left rollback armed.
- `2026-08-24T07:07:55Z`: an immediate accidental rerun was refused because
  `/etc/dgx-setup/canary` already existed. It did not disturb the active canary
  or rollback timer.
- `2026-08-24T07:17:29Z`: the timer launched exact deactivation.
- `2026-08-24T07:17:30Z`: systemd recorded the rollback service and timer as
  deactivated successfully with result `success` and exit status 0.

No `register-profile` command ran. Neither upstream registration path appeared.

## Corrected active-state evidence

Before asking for human confirmation, the helper proved:

- all five managed symlinks resolved to their exact immutable payloads;
- the state was version 1 with exactly the five reviewed file paths, no backed
  up files, and exactly the three reviewed service keys;
- every forbidden PATH, boot-link, userborn, wrapper, and
  `/run/current-system` path remained absent;
- both upstream registration paths remained absent;
- the direct pilot root still retained the exact candidate;
- `/etc/nix/nix.conf`, `/etc/passwd`, `/etc/group`, and `/etc/shadow` still
  matched the fresh snapshot hashes;
- the canary service and manager target were active with no pending reload;
- all seven factory/access services remained active;
- systemd remained `running` with zero failed units;
- the GB10 query succeeded with driver 580.173.02; and
- sanitized Tailscale state remained `Running`/online with `WantRunning=true`
  and `RunSSH=true`.

This closes the false assertion that ended attempt 1: the resolved-payload
comparison works against the live host.

## Timed rollback evidence

The journal shows exact deactivation removing the five managed links, stopping
the canary service and manager target, reloading systemd, and writing the empty
state. It again emitted the already-investigated non-fatal duplicate stop
warning for `system-manager.target`; the first stop succeeded, the second found
the target unloaded, and the rollback process still exited 0.

A read-only audit after the later reboot, recorded in
[the 2026-09-01 reboot audit](2026-09-01-post-reboot-audit.md), confirmed:

- all five managed paths and every forbidden path are absent;
- the state is the exact empty version-0 rollback record;
- both upstream registration paths are absent;
- the candidate remains valid and directly retained by the pilot root;
- the transient rollback and canary units are unloaded and inactive; and
- systemd, Nix, Tailscale/Tailscale SSH, GDM, Docker, DGX Dashboard, NVIDIA
  persistence, and the GPU are healthy.

The second snapshot's protected-file hashes were checked immediately before and
after activation by the helper. On 2026-09-01, Armen also ran the root-only
post-deactivation check against that same snapshot; `sha256sum -c` reported
`OK` for `/etc/nix/nix.conf`, `/etc/passwd`, `/etc/group`, and
`/etc/shadow`. The previously disclosed evidence gap is closed.

## Residual state and next gate

The only intentional residual artifacts are:

- `/var/lib/system-manager/state/system-manager-state.json`, containing the
  exact empty version-0 record; and
- `/nix/var/nix/gcroots/dgx-setup-root-canary-pilot`, pointing directly to the
  exact candidate.

Neither is an active configuration or registered generation. Do not delete
either merely to make every path absent. A future retained attempt requires a
new same-window private snapshot, a fresh automatic preflight, verified local
console access, and new explicit activation authorization.
