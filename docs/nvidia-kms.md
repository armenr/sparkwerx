# NVIDIA KMS and the desktop roles

[Desktop modes](desktop-modes.md) · [Remote desktop](remote-desktop.md)

Hyprland is the selected desktop for Armen's local and remote use. Keep the
factory Ubuntu GNOME/Xorg session as the familiar alternate and recovery
desktop. KDE remains a future optional role; discussing XFCE does not install
it. Compute-only `headless` still stops the graphical sessions and streaming.

NVIDIA DRM kernel modesetting (KMS) exposes the display interface needed by
our native Hyprland path. It does not itself launch a desktop or replace CUDA.
Enabling it is an optional host-configuration exception, not a new GPU driver.
Other hosts keep their factory setting unless they select and validate this
graphical role.

## Current commands

```bash
./scripts/dgx-kms plan
./scripts/dgx-kms check
```

Both commands inspect only. `plan` reads the repository's proposed policy.
`check` builds the small Nix-packaged inspector and its offline tests as the
normal user, then asks sudo to read protected boot configuration. It reports
the loaded KMS/fbdev booleans, factory override, GNOME policy, GRUB first-entry
kernel/initrd match, pending boot selections, storage compatibility clues,
and relevant unit states. It omits raw boot arguments, UUIDs, entry names,
environment values, and Tailscale identity.

`KMS_STATUS=BOOT_REVIEW_REQUIRED` means the inspection completed, not that
boot recovery or KMS has been tested. `reviewFindings` lists discrepancies to
resolve. Even an empty list is not activation approval. No enable, arm, persist,
or reboot command is implemented yet.

The inspector's tests use synthetic boot configuration and mocked host reads.
They check private-data filtering, pending boot selections, unsupported layouts,
and the read-only command set. Build them with
`nix build --no-link .#kms-preparation-policy`; run the repository checks with
`./scripts/dev check`. These tests do not exercise an actual KMS boot.

## First trial and recovery

The proposed first trial is a separate GRUB entry for the **same factory kernel
and initramfs**, adding only `nvidia_drm.modeset=1`. Keep the usual entry and
its default selection unchanged. Inspect the actual generated GRUB configuration
and its environment storage before implementing this route; do not reconstruct
boot arguments from assumptions or copy another machine's disk identifiers.

GRUB can select an entry once and clear that selection before entering the
kernel. But its own `grub-reboot` helper warns that the selection can persist
when GRUB cannot write its environment block, including some LVM/RAID setups.
The inspector only recognizes the expected header and storage clues. It cannot
prove that firmware loads this GRUB, or that GRUB can write at boot. Those need
verification before advertising automatic next-boot fallback.

Independent console/power recovery must be available for the actual trial.
A userspace rollback timer cannot recover a kernel that hangs before systemd
starts, and a one-shot entry does not power-cycle a hung machine. A reboot is
separate from preparation and is never performed by the current command.

Keep the host in its existing headless mode for the initial KMS boot. Check
access and GPU compute first, then rerun the temporary Hyprland capture test.
Only after capture works should we advance to local GDM integration and actual
Sunshine/Moonlight streaming. Retest idle resource use and compute alongside
streaming; enabling a capability is not proof of 4K/120 performance.

Permanent enablement comes later, through reviewed Nix-managed configuration
and its own rollback. Preserve NVIDIA's driver/package and the vendor override
as fallback material. Account for initramfs copies: the factory override
package's install/remove hooks call `update-initramfs -u`. Do not purge the
package, edit its file, reload GPU modules, or regenerate boot images as an
incidental diagnostic step.

KMS may make GNOME Wayland eligible again. Preserve GNOME's Xorg session policy
explicitly when implementing the graphical fallback; don't conflate enabling
KMS with migrating the factory desktop to Wayland. Session selection, portals,
input/audio permissions, and remote sharing versus separate sessions remain
their own integration work.

## Why the factory override is not the whole answer

Investigation on 2026-09-06 found:

- NVIDIA still publishes `nvidia-drm-options-modeset0` 25.07-1, described as
  a compatibility override. Its changelog references internal issue 5345386
  without a public technical explanation.
- In a [Spark-specific reply](https://forums.developer.nvidia.com/t/dgx-os-support-for-wayland-over-x11/348199/3),
  NVIDIA employee `aplattner` explains the factory Ubuntu desktop's missing
  explicit synchronization. This explains the X11 preference, but does not
  establish every reason for the separate KMS override.
- The pilot's installed Mutter 46.2-1ubuntu0.24.04.16 still carries Ubuntu's
  `wayland-Disable-linux-drm-syncobj-v1.patch`. The matching source package
  was inspected; [Ubuntu's release-policy discussion](https://lists.ubuntu.com/archives/ubuntu-release/2024-May/006087.html)
  explains the decision. Factory Xwayland is 23.2.6.
- Our pinned Hyprland 0.56.2 has explicit-sync protocol support; upstream made
  it the default in [0.50](https://hypr.land/news/update50/). The temporary
  capture test does not use factory Mutter and disables Xwayland.
- NVIDIA's [580.173.02 GBM requirements](https://download.nvidia.com/XFree86/Linux-aarch64/580.173.02/README/gbm.html)
  require KMS. The same driver's [KMS chapter](https://download.nvidia.com/XFree86/Linux-aarch64/580.173.02/README/kms.html)
  retains an experimental warning; neither page certifies this Spark setup.
- A [firsthand Spark report](https://forums.developer.nvidia.com/t/dgx-spark-ota-update-to-dgx-os-7-5-0-kills-all-display-output-when-nvidias-own-nvidia-drm-options-modeset0-package-is-installed/382452)
  describes working KMS/Wayland on the same driver and BIOS string as the
  pilot, but a different kernel revision, and after a power cycle too.
  It is encouraging evidence, not a controlled comparison or NVIDIA clearance.

These findings justify an optional trial, not silently changing every Spark.
The policy lives in [kms-plan.json](../root/graphics/kms-plan.json); the
[Nix artifacts](../root/graphics/kms.nix) are preparation only and do not enter
any active Home or System Manager profile.
