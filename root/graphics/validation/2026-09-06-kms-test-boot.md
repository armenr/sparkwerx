# Pilot KMS test boot

## Result

After Armen performed the one-boot trial reboot, the root status operator
reported `KMS_TEST_BOOT`: loaded `modeset=Y`, a new boot, consumed trial marker,
no pending next entry, unchanged normal GRUB configuration, and retained
recovery code. This is the operator-supplied privileged result; the agent's
noninteractive sudo still required a password.

Trial code was commit `63c59a1d26b0270acb4cf3a202b18d4c0bf4bc45`, with bundle
`/nix/store/jfrv9wzqflbl7c8pwaanpd1ylis01zx3-dgx-kms-trial` and private snapshot
`/var/lib/dgx-setup/kms-trial`. The factory driver and normal boot entry were
not replaced. KMS is enabled for this running trial, not permanently configured.

## Postboot checks

Agent checks on 2026-09-06, through 18:48 UTC, found:

- Kernel `6.17.0-1031-nvidia`; GB10 responding through driver `580.173.02`.
- Systemd `running`, no failed units, and no pending reload on checked units.
- The selected root remained
  `/nix/store/djp7ap9gc7kq6c5hhbqzzslvmg4vq3m1-system-manager`.
  System Manager, its canary, and `dgx-headless.target` were active after boot.
- GDM and Dashboard GUI were inactive; Dashboard Admin, Docker, NVIDIA
  persistence, Nix service/socket, and Tailscale were active.
- Tailscale reported `Running`, online, `WantRunning=true`, and `RunSSH=true`.
  Its loaded service fragment remained the Nix-managed `/etc` unit. No raw
  identity, preferences, or addresses were retained.

`./scripts/test-remote-desktop-graphics.sh` passed on this KMS-enabled boot.
All four presets (`smoke`, `1440p120`, `4k60`, `4k120`) passed EGL two-color
readback and 60-frame changing-content encode/decode with H.264, HEVC, and AV1
NVENC. Each run verified unchanged protected service records and selected root.
This is short rendering/encoding evidence, not a sustained FPS measurement or
a general CUDA workload qualification.

The GPU bundle remained
`/nix/store/kknrh29x501yjp8nv5vsnbvf7r4cc550-dgx-remote-desktop-gpu-test`.
The existing capture bundle and policy also built successfully:

- `/nix/store/ssdy1j2z0vf112dl0vmzjxk9v61l8fck-dgx-remote-desktop-session-test`
- `/nix/store/956n5y55ws7nl66r0fk4sf1w4dnnry1j-sparkwerx-private-session-policy`

No compositor, Sunshine service, listener, desktop switch, or further reboot
was started by these postboot checks. No package pins or active profiles changed.

## Next and recovery

Retry the [temporary Hyprland capture test](../../../docs/remote-desktop.md#temporary-capture-test-on-the-pilot).
Its runtime limit, device isolation, and host postflight still apply. Actual
capture, local desktop integration, and Sunshine/Moonlight remain unverified.

The trial entry and recovery snapshot/code remain; there is no confirmation
timer. `./scripts/dgx-kms cancel` removes only this trial's boot entry and
selection, retaining its evidence and loaded KMS until another reboot. It was
not run as incidental cleanup. Follow the [KMS runbook](../../../docs/nvidia-kms.md)
before changing boot state again.
