# Persistent KMS configuration and rollback tooling

Date: 2026-09-07

Repository implementation and offline checks passed. No persistent KMS setting
has been deployed and the new factory-fallback menu has not booted on hardware.

Armen approved this implementation after the successful one-boot KMS/Moonlight
experiment returned to factory KMS off on a later normal reboot. See
[D-022](../../../docs/decision-register.md#d-022-optional-persistent-kms-after-the-successful-one-boot-trial)
and the [operator contract](../../../docs/nvidia-kms.md#persistent-kms-optional-boot-configuration).

## Artifacts

| Artifact | Output |
| --- | --- |
| Operator | `/nix/store/kzjrqwgbbji4xbs7sibmh7fqsrc0xkj4-dgx-kms-persistent` |
| Enabled policy | `/nix/store/g6ndn13f8wf7bi00wwj5bv48d3pyc20v-dgx-kms-persistent-policy` |
| Disabled policy | `/nix/store/waqsgi3pyx7w35pq4zm5zqhvy46l7dz3-dgx-kms-persistent-policy` |

The operator's store closure is 32 paths / 231,089,080 NAR bytes (220.4 MiB).
These reuse existing root-lane dependencies; this is closure size, not an
additional download or installed user profile. No dependency pins changed.

## Checks performed

- Both Nix policy builds passed all 25 KMS tests, including enabled/disabled
  configuration, real GRUB syntax parsing, exact fallback body, changed kernel
  selection, conflicting boot arguments, foreign file/root collisions, stale
  inputs, failed generation/postflight, interrupted publication, exact recovery,
  idempotence, private snapshot modes, and disable after simulated OS updates.
- The complete `./scripts/dev check` passed: 224 tests, five expected skips,
  shell/Python/Nix checks, documentation validation, and flake invariant
  evaluation. The KMS configuration test skipped outside its Nix package
  environment; both package policies supplied and checked that configuration.
- The ordinary-user `dgx-kms-persistent plan` front door built successfully and
  reported the selected pilot, exactly two managed configuration paths, the
  generated GRUB path, factory-fallback ID, and no reboot/driver replacement.
- The old `kms-preparation-policy` still built unchanged.

The transaction tests use private temporary filesystem fixtures and simulated
factory generation/failures. They do not claim a complete Ubuntu boot or a
physical fallback test. Live activation additionally executes the installed
Ubuntu generator, compares its output, and uses the factory syntax checker.

## Unchanged existing evidence

Evaluation preserved these exact outputs:

- headless generation five:
  `/nix/store/djp7ap9gc7kq6c5hhbqzzslvmg4vq3m1-system-manager`;
- one-boot KMS operator:
  `/nix/store/jfrv9wzqflbl7c8pwaanpd1ylis01zx3-dgx-kms-trial`;
- Sunshine:
  `/nix/store/3j2b6777c4i5kvikzw4ghfjz6qmfhafj-sunshine-2026.516.143833`;
- changing-frame test:
  `/nix/store/bhb4pay8ban7lp9idlqam651c3lyn5by-dgx-remote-desktop-sunshine-frames-test`;
- input test:
  `/nix/store/f63h4mqn8dxfii4hvgrzpgzp6vps1mr2-dgx-remote-desktop-input-test`;
- Moonlight trial:
  `/nix/store/g9sk4c25160niyyjhp1jmbbc6qy8389y-sparkwerx-moonlight-trial`.

Read-only host inspection still found exact selected generation five, active
headless/Tailscale/Docker/NVIDIA persistence, inactive GDM, and no pending reload
on those units. No activation, boot file write, driver/module change, service
operation, desktop switch, or reboot was performed. The privileged preflight
could not be run unattended because sudo requires Armen's password.

Next: `./scripts/dgx-kms-persistent check`. Activation remains a separate
decision after that result and independent local recovery confirmation.
