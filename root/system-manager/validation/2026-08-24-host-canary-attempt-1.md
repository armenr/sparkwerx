# System Manager host canary attempt 1 — 2026-08-24

This record documents the first bounded live activation of the exact System
Manager canary on `sparkle-01`. The canary activated successfully, but the
guarded helper stopped on an incorrect symlink assertion and deliberately left
the timed rollback armed. The exact deactivation program ran on schedule and
clean postflight passed.

The result is **PASS for activation boundary and timed rollback**, but **not a
retained host activation**. System Manager is currently inactive and
unregistered.

## Exact inputs

| Field | Value |
| --- | --- |
| Host | `sparkle-01` |
| Candidate | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| Candidate revision | `05e08c6dd739d7f3204e71322594bb8095334cfb` |
| Private Nix | 2.35.2 |
| Activation helper commit | `731c0ae` |
| Snapshot | `inventory/sparkle-01/raw/system-manager-canary/20260823T222131Z` |
| Disposable test derivation | `/nix/store/jcrdk9p9lz3qiya2l1021339lsdvyxcg-container-test-dgx-root-canary.drv` |
| Disposable test result | PASS; still matches the candidate |
| Authorization | Explicit approval for this host canary only |
| Recovery | Independent local console available; Tailscale SSH remained healthy |

The private snapshot was root-owned, mode 0700, checksum-valid, and bound to
the exact candidate. Immediately before activation, all managed, state,
registration, and pilot-root paths were absent. The seven protected services,
system health, GPU query, and sanitized Tailscale checks passed.

## Activation timeline

- `2026-08-24T06:25:55Z`: the helper verified the snapshot and preflight.
- It created the direct pilot root
  `/nix/var/nix/gcroots/dgx-setup-root-canary-pilot` pointing to the exact
  candidate.
- It armed `dgx-root-canary-rollback.timer` for ten minutes, with the transient
  service bound to the exact candidate's `bin/deactivate` program.
- Low-level activation completed and wrote the version-1 manager state.
- Automatic postflight then failed on the helper's canary-symlink target
  comparison. The helper exited without stopping the rollback timer.
- `2026-08-24T06:35:55Z`: the timer launched exact deactivation.
- `2026-08-24T06:35:56Z`: deactivation exited 0; the transient timer and
  service were collected and unloaded.

No `register-profile` command ran. Neither upstream registration path ever
appeared.

## Active-state evidence before rollback

Read-only inspection while the timer remained armed confirmed:

- the state had version 1;
- `fileTree.files` contained exactly the five reviewed canary paths;
- `fileTree.backedUpFiles` was empty;
- `services` contained exactly `dgx-setup-canary.service`,
  `sysinit-reactivation.target`, and `system-manager.target`;
- the canary service and manager target were active;
- all seven protected services remained active with `NeedDaemonReload=no`;
- systemd remained `running` with no failed units;
- the GB10 GPU query succeeded with driver 580.173.02; and
- sanitized Tailscale state remained `backend=Running`, `online=true`,
  `WantRunning=true`, and `RunSSH=true`.

## False postflight assertion

The candidate manifest's `dgx-setup/canary` source is the wrapper directory
`/nix/store/79jrmrd1q3c0cjjab03kzg8ya9wgdkki-dgx-setup-canary-etc-link`.
Inside it, `dgx-setup/canary` resolves to the actual immutable payload
`/nix/store/ggzxq8n553bw886mcq11y9yx76fgp3k8-etc-canary`.

System Manager correctly installed the host link directly to that payload. The
first helper incorrectly compared the host target with the wrapper directory.
The exact disposable-test build log independently shows the engine flattening
the wrapper and linking the same payload. This was a verifier defect, not a
candidate ownership violation.

Commit `0d02309` changes live verification to compare fully resolved immutable
payloads. The corrected assertion was checked against the exact candidate and
observed payload, and the repository evaluation suite passed.

## Deactivation log warning

The rollback journal contained a non-fatal error saying that
`system-manager.target` was not loaded. Exact pinned-source inspection explains
the warning:

1. the saved service map already contains `system-manager.target`;
2. `services::deactivate` converts that map to its stop list and then appends
   `system-manager.target` again;
3. the first stop succeeds; the duplicate stop finds the target already
   stopped/unloaded; and
4. upstream `for_each_unit` logs individual stop errors but deliberately does
   not propagate them.

The source includes a TODO asking whether those individual failures should be
propagated. The engine then reloaded systemd, wrote the exact empty state, and
exited 0. A later transient-unit cleanup message occurred after systemd had
already reported the rollback service deactivated successfully. Both warnings
are retained here rather than being hidden; the final state and health checks
are the rollback verdict.

## Clean rollback postflight

The following all passed after the timer fired:

- all five managed canary links were absent;
- all global PATH, boot-link, userborn, wrapper, and `/run/current-system`
  forbidden paths were absent;
- the System Manager profile and upstream generation GC root were absent;
- `/var/lib/system-manager/state/system-manager-state.json` was exactly
  `{"fileTree":{"files":[],"backedUpFiles":[]},"services":{},"version":0}`;
- the pilot GC root still pointed directly to the exact candidate;
- Nix daemon, Tailscale, GDM, Docker, both DGX Dashboard services, and NVIDIA
  persistence were active with `NeedDaemonReload=no`;
- systemd was `running` with zero failed units;
- the GB10 GPU query succeeded with driver 580.173.02;
- sanitized Tailscale state remained `Running`/online with `WantRunning=true`
  and `RunSSH=true`; and
- Armen's root-only check reported `OK` for the snapshot hashes of
  `/etc/nix/nix.conf`, `/etc/passwd`, `/etc/group`, and `/etc/shadow`.

## Residual state and retry gate

Two deliberate artifacts remain:

- the exact empty version-0 System Manager state file; and
- the direct pilot GC root retaining the exact candidate and rollback tools.

Neither is an active configuration or registered generation. Do not delete
either merely to regain an all-absent preflight. The helpers may accept only
this exact empty state and this exact direct root on a future retry; anything
else is a stop condition.

A retry requires a fresh same-window private snapshot, current automatic
preflight, independent console access, and new explicit activation
authorization. The candidate and its passed disposable derivation have not
changed.
