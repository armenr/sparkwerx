# System Manager first-registration host attempt 3 — 2026-09-01

This record documents the first retained live System Manager generation
registration on `sparkle-01`. The corrected guarded wrapper passed every
snapshot, preflight, transaction, and postflight check. Armen verified the
independent physical console, entered exactly `KEEP REGISTRATION`, repeated
postflight passed, and the registration-only rollback timer was disarmed.

The result is **PASS for retained first-generation registration**. The exact
five-path/three-service canary remains the live activation. Registration added
only the reviewed two-link Nix profile and direct upstream extra GC root. It
performed no activation, reactivation, boot linkage, daemon reload, service
restart, pilot-root removal, broader root-role change, desktop switch, or
Tailscale migration.

The current state class is `ACTIVE_REGISTERED_RETAINED`.

## Exact inputs

| Field | Value |
| --- | --- |
| Host | `sparkle-01` |
| Candidate | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| Repository commit | `0f03d01d46e9fbd340676d8c91d4f2697bd25ce4` |
| Private snapshot | `inventory/sparkle-01/raw/system-manager-registration/20260901T201613Z` |
| Snapshot state | `ACTIVE_RETAINED` with exact registration surface absent |
| Transaction SHA-256 | `86c4be22ed350782920905897d80616b3949998d2662fd04ab9d1f5c3f4078a9` |
| Transaction-test derivation | `/nix/store/lxnykcyvjn18pdv7y9rr1ryhvjgicazg-container-test-dgx-root-canary-registration-transaction.drv` |
| Wrapper start | `2026-09-01T20:19:12Z` |
| Registration completion | `2026-09-01T20:19:13Z` |
| Snapshot age at wrapper validation | 170 seconds |
| Authorization | Explicitly bound to snapshot `20260901T201613Z` |
| Recovery | Physical keyboard, display, and local terminal verified |

The private snapshot was root-owned, mode 0700, checksum-valid, and bound to
the exact candidate, transaction, repository commit, active canary state,
protected files, and protected-service process identities.

## Retained registration timeline

- The snapshot helper recorded `ACTIVE_RETAINED` with the complete
  registration surface absent and performed no host mutation.
- Armen verified the local console and explicitly authorized registration
  using snapshot `20260901T201613Z`.
- `2026-09-01T20:19:12Z`: the wrapper began and accepted the snapshot at 170
  seconds old.
- Preflight confirmed the exact active-unregistered canary, absent registration
  and boot surfaces, intact pilot root, unchanged protected processes, healthy
  system/GPU, and healthy sanitized Tailscale SSH.
- `20:19:13Z`: the exact ten-minute registration-only rollback timer was armed
  before mutation.
- The exact snapshot transaction invoked the candidate's `register-profile`,
  verified generation one and the extra root, and changed no live activation
  or service.
- Automatic postregistration passed the exact links, unchanged version-1
  manager state, protected-file hashes, protected processes, system/GPU, and
  sanitized Tailscale checks.
- Armen reverified the physical console and entered exactly
  `KEEP REGISTRATION`.
- The wrapper repeated the complete automatic postflight successfully and
  stopped the rollback timer.
- Independent read-only postflight at `20:20:13Z` found both transient rollback
  units unloaded/inactive and classified the host
  `ACTIVE_REGISTERED_RETAINED`.

The rollback service never ran.

## Exact registration surface

The root-owned profile directory is mode 0755 and contains exactly:

| Path | Raw target | Resolved target |
| --- | --- | --- |
| `/nix/var/nix/profiles/system-manager-profiles/system-manager` | `system-manager-1-link` | exact candidate |
| `/nix/var/nix/profiles/system-manager-profiles/system-manager-1-link` | exact candidate | exact candidate |

The upstream extra root is:

| Path | Raw and resolved target |
| --- | --- |
| `/nix/var/nix/gcroots/system-manager-current` | exact candidate |

The pre-existing pilot root remains:

| Path | Raw and resolved target |
| --- | --- |
| `/nix/var/nix/gcroots/dgx-setup-root-canary-pilot` | exact candidate |

“Exact candidate” means:

    /nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager

No second generation, unknown profile entry, or foreign collision exists.

## Live activation and forbidden boundaries

The live manager state remained byte-identical to the private snapshot through
both wrapper postflights. The active surface is still exactly the original five
managed filesystem paths and three service keys recorded by
`2026-09-01-host-canary-attempt-3.md`. Registration did not activate or
reactivate them.

These remain absent:

- `/etc/systemd/system/default.target.wants/system-manager.target`;
- `/etc/profile.d/system-manager-path.sh`;
- `/etc/environment.d/10-system-manager.conf`;
- `/etc/systemd/system/system-manager-path.service`;
- `/etc/systemd/system/userborn.service`;
- `/run/wrappers`; and
- `/run/current-system`.

The registration owns no NVIDIA, Tailscale, GDM, Docker, DGX Dashboard, Nix
daemon, user, group, wrapper, PATH, portal, or desktop configuration.

## Protected health

Both wrapper postflights and the independent postflight found all seven
protected services active with the same process identities captured by the
snapshot, their original fragments, and `NeedDaemonReload=no`:

| Unit | Main PID |
| --- | ---: |
| `nix-daemon.service` | 33487 |
| `tailscaled.service` | 2143 |
| `gdm.service` | 2267 |
| `docker.service` | 2405 |
| `dgx-dashboard.service` | 1577 |
| `dgx-dashboard-admin.service` | 1576 |
| `nvidia-persistenced.service` | 1615 |

Systemd was `running` with zero failed units. The GPU reported NVIDIA GB10,
driver 580.173.02, P8, and 34°C. Sanitized Tailscale state remained backend
`Running`, online, with `WantRunning=true` and `RunSSH=true`. No raw Tailscale
identity, address, node, or tailnet data is recorded.

## Current operating rules

- Use
  `./scripts/audit-root-canary-state.sh <exact-candidate> registered-first`
  for read-only classification. `ACTIVE_REGISTERED_RETAINED` is the expected
  result.
- Do not rerun `register-root-canary-pilot.sh`. Its required absent
  registration pre-state no longer exists.
- Do not remove or rewrite the selected profile, generation-one link,
  `system-manager-current` root, or pilot root without a separately reviewed
  rollback/switch plan and explicit authorization.
- Keep the private snapshot and its root-owned transaction copy intact. It is
  recovery evidence, not repository content, and must not be committed.
- Do not add boot linkage or treat registration as boot persistence. A normal
  reboot will not start `system-manager.target`; reboot behavior requires a
  separate reviewed and guarded milestone.
- Do not update the candidate, private Nix runtime, System Manager input,
  safety patch, transaction, or generation underneath the retained live state.
- Registration installs no fleet CLI base or application. Home Manager
  activation and every real service/desktop/Tailscale ownership change remain
  separate gates.

Exact registration-only rollback remains available in the private snapshot:

    sudo /home/n0b0dy/Development/DGX-setup/inventory/sparkle-01/raw/system-manager-registration/20260901T201613Z/root-registration-transaction.sh \
      rollback-first \
      /nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager

Run it only under separately explicit rollback authorization, then require
`ACTIVE_RETAINED`, the complete registration surface absent, the pilot root
intact, and full protected postflight.

The next System Manager milestone is a separate decision. This retained
generation is not authorization for boot linkage, a second generation,
generation switching, broader root ownership, or activation of a real managed
service.
