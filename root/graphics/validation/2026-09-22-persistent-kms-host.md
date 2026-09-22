# Persistent KMS: successful pilot reboot

Armen ran the corrected operator from commit `785a94c`, then separately
rebooted `sparkle-01`. His privileged status output reported:

```text
KMS_STATUS=PERSISTENT_KMS_ACTIVE
modeset=Y
persistentConfiguration=true
fallbackEntry=sparkwerx-factory-kms-off
```

The preceding enable reported `PERSISTENT_PENDING_REBOOT` while loaded KMS
was still `N`. Together with the explicit reboot report, the later status
establishes persistent KMS on an ordinary boot, not another one-boot trial.
`rebootPerformed=false` in the status JSON means the status command itself
did not reboot the machine.

Read-only checks confirmed the retained operator and deployed Nix links:

- Operator: `/nix/store/d3jx2shywafyzyq5prcwjnkdh7vdhcg5-dgx-kms-persistent`.
- Configuration: `/nix/store/ivjv5srzsxcka8nn740npbl9p0hxqv4j-dgx-kms-persistent-configuration`.
- `/etc/default/grub.d/zz-sparkwerx-kms.cfg` and
  `/etc/grub.d/42_sparkwerx_kms` resolve into that configuration.
- Kernel `6.17.0-1031-nvidia`; responding NVIDIA GB10 driver `580.173.02`.
- System Manager still selects headless generation five; GDM is inactive
  and Tailscale is active.

The loaded-parameter and generated-fallback verdict above comes from the
user's privileged operator output. Private boot files were not independently
reread by the agent. The physical KMS-off fallback boot, sustained 4K/120
streaming, audio, and persistent desktop integration remain separate work.

Use `./scripts/dgx-kms-persistent status` to inspect this deployment. Preserve
its recovery snapshots/code roots and the spent one-boot trial. No new enable,
cleanup, driver change, desktop switch, or reboot is needed to resume the
[temporary Moonlight trial](../../../docs/moonlight-trial.md).
