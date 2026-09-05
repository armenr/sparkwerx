# Desktop headless host attempt 2 — 2026-09-05

## Result

**PASS; EXACT GENERATION FIVE IS LIVE, CONFIRMED, AND HEADLESS.**

The corrected guarded operator moved `sparkle-01` from exact System Manager
generation four/factory GNOME to exact generation five/headless mode. It first
created a private snapshot, preserved the superseded first-attempt candidate,
selected the corrected candidate root, and armed persistent ten-minute
generation-four/factory-GNOME rollback. Only then did its detached worker
register, activate, and isolate the headless generation.

The automatic postflight and the separately invoked status both verified exact
headless state, unchanged Nix-managed Tailscale identity and SSH, healthy GPU
and systemd state, and unchanged mode-independent factory services. Confirmation
repeated those checks, stopped the timer, verified the rollback service had not
run, removed the complete guard surface, and retained generation five. The
operator performed no reboot.

## Exact transaction

| Field | Value |
| --- | --- |
| Host | `sparkle-01` |
| Repository commit | `fc82217c7b85ed8ea42b2e08783dbfe2b9a05385` |
| Snapshot | `inventory/sparkle-01/raw/desktop-mode-switch/20260905T153316Z` |
| Command authorized | `scripts/dgx-desktop headless` |
| Command started | `2026-09-05T15:32:55Z` |
| Rollback armed | `2026-09-05T15:33:17Z` |
| Generation five activated | `2026-09-05T15:33:19Z` |
| Status independently checked | `2026-09-05T15:39:18Z` |
| Confirmation completed | `2026-09-05T15:39:27Z` |
| Starting/rollback generation | `/nix/store/vjw778sf95r42a1zbivlk8z4p45y7qhx-system-manager` |
| Retained headless generation | `/nix/store/djp7ap9gc7kq6c5hhbqzzslvmg4vq3m1-system-manager` |
| Guarded switch bundle | `/nix/store/4148r540pysd6017n7j6fvyiv7541gzq-dgx-desktop-switch` |
| Resulting state SHA-256 | `e8c8aa8aed797fdd44d087225e66ebf061a50b159d45f84ec5620714fec61f74` |
| Reboot performed | No |

## Exact retained generation surface

| Profile generation | Store output |
| --- | --- |
| 1 | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| 2 | `/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager` |
| 3 | `/nix/store/w8kn2idc0ix6x1024qphv2fvmaf664d7-system-manager` |
| 4 | `/nix/store/vjw778sf95r42a1zbivlk8z4p45y7qhx-system-manager` |
| 5, selected/live/upstream-rooted | `/nix/store/djp7ap9gc7kq6c5hhbqzzslvmg4vq3m1-system-manager` |

All five numbered profiles and their direct pilot roots remain. The normal
headless root now retains the corrected generation-five output. The exact
first-attempt candidate remains recoverable at the separate historical root:

```text
/nix/var/nix/gcroots/dgx-setup-desktop-headless-pre-dashboard-pilot
  -> /nix/store/20qw0af0jwfqi5spgg3b1nrc0yydhlc1-system-manager
```

No generation or recovery anchor was deleted.

## Verified live mode

- `default.target` is the generation-five headless dispatcher;
- `dgx-headless.target`, `multi-user.target`, and `system-manager.target` are
  active;
- `graphical.target`, factory GDM, the GNOME orchestration target, and the
  user-facing `dgx-dashboard.service` are inactive;
- factory GNOME/GDM and Dashboard packages and unit files remain installed;
- `dgx-dashboard-admin.service`, Docker, and NVIDIA persistence remain active
  and retained their exact same-boot process/service identity;
- `tailscaled.service` remains active from the Nix-managed unit, with backend
  running, node online, `WantRunning=true`, `RunSSH=true`, and identity
  unchanged;
- NVIDIA GB10/driver 580.173.02 health passed;
- systemd reports `running` with zero failed units; and
- System Manager state version 1 records exactly 12 paths and four managed
  service keys: the canary, System Manager target, sysinit reactivation target,
  and Nix-managed Tailscale.

## Rollback and persistence state

The rollback timer was armed before mutation and never fired. Confirmation
removed `/var/lib/dgx-setup/desktop-switch`, the rollback bundle root, both
rollback unit links, and the timer enablement link. No desktop rollback is now
armed.

Generation five owns the reviewed `/etc/systemd/system/default.target`
dispatcher, so headless is the persistent declared boot mode. The disposable
three-reboot lifecycle already proves this exact candidate's cold-boot graph.
This host attempt did not perform a real generation-five reboot; any such reboot
remains a separate operator action and authority boundary.

## Current authority

The current host classifier is
`ACTIVE_REGISTERED_GENERATION_FIVE_HEADLESS_TAILSCALE_NIX_MANAGED`.
This record supersedes host attempt 1 as live desktop-state authority. The
[Dashboard-aware disposable record](2026-09-05-dashboard-aware-stack.md)
remains the exact implementation/test authority.

Use only `scripts/dgx-desktop` for future desktop status or reviewed transitions.
Do not invoke raw System Manager activation, `register-profile`, or
`systemctl isolate`; do not remove any profile generation or pilot root; and do
not infer authority for a reboot, GNOME return, Hyprland activation, or package
cleanup from this successful headless switch.
