# Tailscale migration host attempt 2 — retained after reboot

Status: **PASS; current live ownership authority for `sparkle-01`.**

The guarded migration ran from repository commit
`f57e51d142db30edfe44fd4d6694d22a822a6d24` with private snapshot
`inventory/sparkle-01/raw/tailscale-migration/20260905T084503Z`.
Before changing the host, the operator re-ran the complete disposable
apt-to-Nix lifecycle and verified that the apt and Nix Tailscale 1.102.3
binaries were byte-identical.

The detached worker registered and activated exact System Manager generation
four, restarted only `tailscaled.service`, and preserved the existing mutable
node identity. As expected, that restart disconnected the active Tailscale SSH
session. A fresh Tailscale SSH connection succeeded immediately, and same-boot
status reported:

```text
PASS|generation_four|generation four is selected, live, boot-linked, and owns running Tailscale
PASS|tailscale|backend=Running;online=true;WantRunning=true;RunSSH=true;identity=unchanged
MIGRATION_STATUS=AWAITING_REBOOT
```

One separately authorized real reboot followed while the persistent rollback
remained armed. Tailscale SSH reconnected after boot. The post-boot check found
systemd running with no failed units, the GPU healthy, all five continuously
protected factory services loaded from their original fragments, and the same
healthy Tailscale identity and SSH preference. It reported
`MIGRATION_STATUS=AWAITING_CONFIRMATION`.

`./scripts/dgx-tailscale confirm` repeated those checks and then removed the
rollback guard:

```text
PASS|confirmation|generation four retained; Nix owns running Tailscale
APT_FALLBACK_RETAINED: no apt package or repository was removed.
REBOOT_VERIFIED: confirmation ran after a separately performed guarded reboot.
```

## Retained state

- Selected profile: `system-manager-4-link`.
- Live root: `/nix/store/vjw778sf95r42a1zbivlk8z4p45y7qhx-system-manager`.
- Running unit fragment: `/etc/systemd/system/tailscaled.service`, supplied by
  the Nix-managed System Manager generation.
- Tailscale package: exact stable ARM64 1.102.3.
- Node identity, state path, online state, and Tailscale SSH remained unchanged.
- The generation-four pilot GC root remains as a recovery anchor.
- The migration state directory, rollback units, rollback root, and timer are
  absent; no migration rollback is armed.
- The apt package and repository remain installed only as deliberate rollback
  material. They no longer own the loaded service or running daemon.

This attempt did not remove apt fallback material, alter enrollment or tailnet
policy, switch the desktop, enable a workload, or change any other factory
service. Apt cleanup, if desired later, is a separate reviewed operation.
