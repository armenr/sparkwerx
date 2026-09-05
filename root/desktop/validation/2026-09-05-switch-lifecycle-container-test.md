# Guarded desktop-switch lifecycle result — 2026-09-05

## Result

**PASS.** The exact guarded desktop-switch operator and persistent rollback
bundle completed all seven disposable lifecycle subtests. The host-boundary
wrapper then proved that `sparkle-01` remained on exact System Manager
generation four with factory GNOME, Nix-managed Tailscale, a clean systemd
state, unchanged protected-service identities, and no desktop-controller or
rollback surface.

## Exact evidence

| Field | Value |
| --- | --- |
| Repository commit under test | `8ab5dd86e72322489dee41a7bedfafde38529276` |
| Verified at (UTC) | `2026-09-05T12:35:10Z` |
| Test derivation | `/nix/store/2pjvrigr248rx344kigkh0w5cqkgqyvn-container-test-dgx-desktop-switch-lifecycle.drv` |
| Test output | `/nix/store/lizh586mhdqg9jn8kpd40ip9c0wzw86h-container-test-dgx-desktop-switch-lifecycle` |
| Output SHA-256 (SRI) | `sha256-+J+OhRQ936+VaqK5JYFHA98AlKYKMBbcQMCl3Nvftlc=` |
| Output SHA-256 (Nix base32) | `0mxnvzdxr9f083f1cc0alsa01pq38y0jbfd2daaszprx2j2qx7zq` |
| Output NAR size | 8,360 bytes |
| Disposable reboots | 1 |
| Live-host mutation | None |
| Live-host postflight | Clean |

The root-local wrapper was:

```bash
sudo ./scripts/test-desktop-switch-lifecycle.sh
```

Nix printed its known top-level warning that `auto-allocate-uids` was ignored
without its experimental feature. The direct local-store command supplied the
required UID-range and cgroup features explicitly; the derivation completed
successfully and the wrapper exited zero. The warning is not a failed gate.

## Passed subtests

1. Install exact generation four and the factory-GDM fixture.
2. Verify the rollback service and timer are valid and isolation-resistant.
3. Automatically roll an unconfirmed same-boot headless switch back to factory
   GNOME while preserving the Tailscale process.
4. Retain a confirmed headless switch after guard cleanup.
5. Perform exact factory rollback to prepare the reboot case.
6. Carry the persistent guard across one reboot and automatically restore
   factory GNOME.
7. Retain all five exact candidate roots and Nix-managed Tailscale state.

## Authority boundary

This PASS proves that the reviewed operator can safely stage, confirm, or roll
back the exact generation-four-to-headless transition under its persistent
ten-minute guard. It makes `scripts/dgx-desktop` eligible for a separately
authorized live pilot.

It did not register or activate generation five on `sparkle-01`, isolate a live
target, stop GDM, switch the desktop, remove a root, clean up a generation, or
reboot the host. Build/test success is not authority for any of those actions.
The live operator itself never performs a reboot.
