# Hyprland virtual-display capture on GB10

Armen ran `./scripts/test-remote-desktop-session.sh` during the successful
[KMS trial boot](../../root/graphics/validation/2026-09-06-kms-test-boot.md).
The 4k120 preset passed: a 3840×2160 virtual output configured at 120 Hz,
NVIDIA GB10 rendering, and red/green pixel readback through Grim. The compositor
and private seat broker stopped; protected host postflight passed.

## Exact run

- Checkout: `fd5583d0ffafa3dc6189436675749d3316cc06cf`.
- Test bundle: `/nix/store/ssdy1j2z0vf112dl0vmzjxk9v61l8fck-dgx-remote-desktop-session-test`.
- Policy: `/nix/store/956n5y55ws7nl66r0fk4sf1w4dnnry1j-sparkwerx-private-session-policy`.
- Private snapshot: `inventory/sparkle-01/raw/remote-desktop-session/20260906T185354Z-ce0074f843d7`.
- Factory kernel `6.17.0-1031-nvidia`, NVIDIA driver `580.173.02`.

The privileged PASS is operator-supplied evidence, not an agent read of the
private log. Independent read-only checks afterward found no remaining
`dgx-capture-test-*` unit, systemd `running`, responsive GB10, and unchanged
selected root `/nix/store/djp7ap9gc7kq6c5hhbqzzslvmg4vq3m1-system-manager`.
Headless remained active, GDM/Dashboard GUI inactive, and Tailscale, Docker,
Dashboard Admin, and NVIDIA persistence active with no pending reload.

## What this establishes

The pinned Hyprland/Nix userspace works with the factory NVIDIA DRM/GBM/EGL
stack in this private session. Its physical outputs were disabled by the test
configuration; no physical-monitor unplug event was required or recorded.
The transient service denied TCP/UDP and input access and had a 150-second
hard limit. No permanent desktop, profile, permission, or boot change occurred.

Grim's image-copy/screencopy readback is not Sunshine's capture path. This was
two verified colors, not a measurement of 120 changing frames per second.
Sunshine capture, Moonlight transport/latency, input/audio, and sustained
performance remain untested. The earlier FFmpeg/NVENC checks are separate
evidence, not a completed Sunshine pipeline.

KMS remains enabled only for the running trial. Its entry, private snapshot,
and recovery code are retained; no cancel, permanent KMS setting, or further
reboot was performed. Next is the separate
[Sunshine startup diagnostic](../../docs/remote-desktop.md#temporary-sunshine-startup-test).
