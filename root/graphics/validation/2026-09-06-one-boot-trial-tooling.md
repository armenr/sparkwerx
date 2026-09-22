# One-boot KMS trial tooling

## Inputs

The operator supplied the root-readable inspection from the preparation at
`ef1eea9fe8710a36659335f347ff8c03a7183e81`. It reported factory-disabled KMS,
no pending boot selection or transition guard, the expected headless services,
and no review findings. The reviewed kernel and GRUB configuration hash are
recorded in [kms-plan.json](../kms-plan.json). Raw boot configuration was not
copied into Git or the Nix store.

## Tested artifacts

- Trial: `/nix/store/jfrv9wzqflbl7c8pwaanpd1ylis01zx3-dgx-kms-trial`.
- Policy: `/nix/store/hq6lyh25f8hdr6q4j9spr58fqy4ycgk5-sparkwerx-kms-preparation-policy`.
- The 39 KMS tests passed locally and in the Nix policy build. Coverage includes
  entry preservation, simulated boot-time marker failure/reuse, synthetic EFI
  routing, interrupted writes, collisions, cancellation, and retry. Real GRUB
  syntax/environment utilities operated only on synthetic temporary files.
- `./scripts/dev check` passed: 116 Python tests, one unrelated skip, lint,
  documentation checks, shell parser checks, and Nix evaluation.
- The complete root-manager artifact manifest matched the prior commit;
  `flake.lock` was unchanged. The evaluated and selected headless root remained
  `/nix/store/djp7ap9gc7kq6c5hhbqzzslvmg4vq3m1-system-manager`.

## Host effects and next step

No trial was armed or booted. No boot configuration, module setting, loaded
driver, service, desktop mode, root profile, or access configuration changed.
Builds added only store objects, not packages to an active profile.

Actual EFI-route checks run privately during arming before boot-state writes.
Firmware marker consumption and a real KMS boot remain untested. Follow the
[trial and recovery operator](../../../docs/nvidia-kms.md#first-trial-and-recovery)
with independent console/power recovery available; reboot is a separate action.
