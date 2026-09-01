# System Manager host canary attempt 3 — 2026-09-01

This record documents the first retained live activation of the exact System
Manager canary on `sparkle-01`. The guarded helper passed every pre-activation
and post-activation check, Armen verified the independent physical console and
entered the exact `KEEP CANARY` confirmation, and the rollback timer was
disarmed. Independent read-only postflight then confirmed the bounded active
state.

The result is **PASS for a retained bounded host canary**. System Manager is
active only on its five-path/three-service canary surface. It remains
unregistered and is not linked into boot.

## Exact inputs

| Field | Value |
| --- | --- |
| Host | `sparkle-01` |
| Candidate | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| Candidate revision | `05e08c6dd739d7f3204e71322594bb8095334cfb` |
| Private Nix | 2.35.2 |
| Activation helper last changed | `cd2e8e5` |
| Repository HEAD at activation | `77a215e` |
| Fresh snapshot | `inventory/sparkle-01/raw/system-manager-canary/20260901T103533Z` |
| Disposable test derivation | `/nix/store/jcrdk9p9lz3qiya2l1021339lsdvyxcg-container-test-dgx-root-canary.drv` |
| Disposable test result | PASS; matched the exact candidate |
| Authorization | Explicitly bound to snapshot `20260901T103533Z` |
| Recovery | Physical keyboard, display, and local terminal verified |

## Expired-snapshot refusal

An earlier snapshot,
`inventory/sparkle-01/raw/system-manager-canary/20260901T100237Z`, was valid
and correctly bound to the same candidate, but the activation invocation began
at `2026-09-01T10:33:03Z`, when the snapshot was 1,813 seconds old. The helper
refused it because the maximum age is 1,800 seconds.

That refusal occurred during snapshot validation, before a rollback timer,
activation, registration, daemon reload, or service change. A read-only
preflight at `10:33:45Z` confirmed the exact empty version-0 state, absent
managed paths, retained candidate, healthy protected services, zero failed
units, healthy GPU, and sanitized Tailscale/Tailscale SSH state.

## Retained activation timeline

- `2026-09-01T10:35:33Z`: the fresh root-owned, mode-0700 snapshot recorded
  the exact empty state, absent registration paths, and existing exact pilot
  root.
- Armen verified the local console and explicitly authorized activation using
  that exact snapshot.
- `2026-09-01T10:37:43Z`: the helper began; the snapshot was 100 seconds old.
- `10:37:44Z`: preactivation passed, the exact ten-minute rollback timer was
  armed, and low-level activation began.
- `10:37:44Z`: System Manager completed activation; automatic postflight
  passed the exact ownership, protected-file, service, system, GPU, and
  sanitized Tailscale checks.
- Armen reverified the physical console and entered exactly `KEEP CANARY`.
- The helper repeated the full automatic postflight successfully.
- `10:37:51Z`: systemd stopped and collected the transient rollback timer.
  The rollback service never ran.

No `register-profile` command ran.

## Retained active boundary

Independent read-only postflight confirmed these five and only these five
managed filesystem paths:

| Host path | Immutable payload |
| --- | --- |
| `/etc/dgx-setup/canary` | `/nix/store/ggzxq8n553bw886mcq11y9yx76fgp3k8-etc-canary` |
| `/etc/systemd/system/dgx-setup-canary.service` | `/nix/store/v2m4k91zvpmbmmr9lg1p4j9iibbl7lqp-unit-dgx-setup-canary.service/dgx-setup-canary.service` |
| `/etc/systemd/system/sysinit-reactivation.target` | `/nix/store/49lsz895j1kih47nynzwfxx8v598443l-unit-sysinit-reactivation.target/sysinit-reactivation.target` |
| `/etc/systemd/system/system-manager.target` | `/nix/store/gckz3b4l4ag5n4f3yrqnc7l9y1jalfhy-unit-system-manager.target/system-manager.target` |
| `/etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service` | The exact canary-service payload above |

The state record is version 1. Its file list is exactly those five paths, its
backed-up-files list is empty, and its service map contains exactly:

- `dgx-setup-canary.service`;
- `sysinit-reactivation.target`; and
- `system-manager.target`.

The canary service is active/exited with result `success`; both targets are
active. The transient rollback timer and service are unloaded and inactive.

## Boundaries that remain absent

- `/nix/var/nix/profiles/system-manager-profiles/system-manager`;
- `/nix/var/nix/gcroots/system-manager-current`;
- `/etc/profile.d/system-manager-path.sh`;
- `/etc/environment.d/10-system-manager.conf`;
- `/etc/systemd/system/default.target.wants/system-manager.target`;
- `/etc/systemd/system/system-manager-path.service`;
- `/etc/systemd/system/userborn.service`;
- `/run/wrappers`; and
- `/run/current-system`.

The direct pilot root still points to the exact candidate. It is the only
deliberate durable retention mechanism and must not be removed while the canary
is active.

## Protected health

Nix daemon, Tailscale, GDM, Docker, both DGX Dashboard services, and NVIDIA
persistence are active from their original fragments with
`NeedDaemonReload=no`. Systemd is `running` with zero failed units. The GPU
query reported NVIDIA GB10, driver 580.173.02, P8, and 37°C. Sanitized
Tailscale state remained backend `Running`, online, with `WantRunning=true`
and `RunSSH=true`.

The helper verified the snapshot hashes for `/etc/nix/nix.conf`,
`/etc/passwd`, `/etc/group`, and `/etc/shadow` immediately before and after
activation.

## Current operating rules

- Do not rerun the inactive-state preflight or activation helper and interpret
  their expected collision failures as drift. The canary is intentionally
  active.
- Do not remove
  `/nix/var/nix/gcroots/dgx-setup-root-canary-pilot`.
- Do not run `register-profile`, add the boot link, broaden the root role,
  migrate Tailscale ownership, or switch desktop mode without a new reviewed
  plan and explicit authorization.
- Do not update the candidate, its private Nix input, patch, or test derivation
  underneath the active canary.
- A normal reboot will not start this canary because
  `default.target.wants/system-manager.target` is intentionally absent.
- Exact low-level deactivation remains:

  ```bash
  sudo /nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager/bin/deactivate
  ```

  Run it only under separately explicit deactivation authorization, then verify
  empty version-0 state and the full protected postflight.

The next root-management milestone is a separate decision. Retaining this
canary does not itself authorize generation registration or a real managed
service.
