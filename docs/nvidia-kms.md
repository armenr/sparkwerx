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

The pilot's [first trial boot passed](../root/graphics/validation/2026-09-06-kms-test-boot.md):
KMS loaded, the one-use marker was consumed, and the normal GRUB configuration
stayed unchanged. Headless/access services and short rendering/encoding checks
passed afterward. [Temporary Hyprland capture also passed](../remote-desktop/validation/2026-09-06-temporary-capture-host.md);
Sunshine's changing-frame encoder tests and a MacBook/Moonlight connection
subsequently passed too. A later normal reboot returned to factory KMS off,
as the one-boot trial was designed to do. Persistent KMS is selected for
the pilot. Its first activation stopped on a factory drop-in ordering conflict;
the corrected operator below still needs its successful host retry and boot.

## Persistent KMS: optional boot configuration

The selection lives in [the pilot's graphics configuration](../hosts/sparkle-01/graphics.nix).
The [Nix adapter](../root/graphics/kms-persistent.nix) defaults to disabled;
only the pilot explicitly selects it. This is separate from the historical
System Manager generations and does not change the headless desktop role.
It is not yet part of generic `dgx-setup converge`.

```bash
./scripts/dgx-kms-persistent plan
./scripts/dgx-kms-persistent check
```

`plan` builds/inspects the candidate without sudo. `check` additionally asks
sudo for read-only host, boot, EFI-route, and access checks. Neither deploys
configuration. The operator's unit tests include real GRUB syntax checks,
failed generation/postflight, interruption recovery, and simulated kernel
updates. They are not evidence that the new menu has booted on this machine.
See the [tooling test record](../root/graphics/validation/2026-09-07-persistent-kms-tooling.md).

After that review and **separate activation approval**, with independent
keyboard/display/power recovery available:

```bash
./scripts/dgx-kms-persistent enable --console-ready
```

This deploys two Nix-store symlinks:

- `/etc/default/grub.d/zz-sparkwerx-kms.cfg`: append
  `nvidia_drm.modeset=1` to ordinary Ubuntu boot entries and show a five-second
  GRUB menu. Ubuntu recovery-mode entries do not inherit that argument.
- `/etc/grub.d/42_sparkwerx_kms`: generate **Sparkwerx: factory settings
  (NVIDIA KMS off)** from Ubuntu's current default kernel entry, with
  `nvidia_drm.modeset=0` and its own unique menu ID.

The `zz-` prefix matters: Ubuntu sources the defaults in filename order, and
the factory `no-grubmenu.cfg` hides the menu. A numeric `90-` prefix loads
before that file, not after it. Keep the factory file installed and unchanged;
the selected override must win, and the generated-menu check must still pass.

The fallback runs the installed Ubuntu `10_linux` generator whenever GRUB is
regenerated. It keeps the current kernel, initramfs, and disk arguments; it
doesn't carry a saved kernel path from installation day. Unknown generator
layouts or conflicting NVIDIA arguments stop generation for review. Nix must
remain available for this hook; its exact code is retained against garbage
collection. This uses the distribution's
[GRUB configuration mechanism](https://www.gnu.org/software/grub/manual/grub/html_node/Simple-configuration.html),
not another bootloader or GPU package.

Before changing either link, the operator saves private recovery material and
retains its Nix executable. It checks that current GRUB can be reproduced,
generates the changed configuration to memory, checks the allowed differences
and syntax, and atomically replaces `/boot/grub/grub.cfg`. It holds the Debian
package-manager locks during the transaction. Don't run other bootloader
maintenance concurrently.

No module is reloaded, no initramfs is rebuilt, and no service or desktop is
started. NVIDIA's override file/package, driver, CUDA, EFI forwarder, GRUB
environment, and every System Manager generation remain untouched. The spent
one-boot trial and its recovery root are retained too. Use the new operator's
`status` after persistent activation; the old trial's unchanged-GRUB check no
longer describes that configuration.

`PERSISTENT_PENDING_REBOOT` means the next ordinary boot enables KMS; it does
not mean KMS is already loaded. Reboot is always separate. After reboot:

```bash
./scripts/dgx-kms-persistent status
```

`PERSISTENT_KMS_ACTIVE` verifies the configuration/fallback and loaded `Y`,
not streaming performance. Check access and GPU health, then resume the
[Moonlight trial](moonlight-trial.md).

### Factory fallback and rollback

If the KMS-enabled boot fails, use the local GRUB menu's **factory settings
(NVIDIA KMS off)** entry. It disables KMS for that boot without changing the
normal default. There is no automatic userspace recovery timer: one cannot
repair a kernel hang before userspace starts. Independent local recovery is
required; the new fallback still needs its first physical boot test.

To return ordinary future boots to factory policy:

```bash
./scripts/dgx-kms-persistent disable
```

This removes only the two exact managed symlinks and regenerates GRUB using
the **current** factory kernels/configuration. It does not restore an old
kernel list over later OS updates. A currently loaded KMS driver remains
loaded until a separate reboot. Initial rollout and normal disable require
the reviewed headless pilot; GNOME/Xorg integration remains separate.

A failed transaction automatically attempts its exact pre-transaction restore.
After a power loss or forced termination during the write, use:

```bash
./scripts/dgx-kms-persistent recover
```

Recovery refuses stale factory inputs or foreign replacements instead of
overwriting them. Do not reboot while it reports `RECOVERY_REQUIRED`. Private
snapshots stay under `/var/lib/dgx-setup/kms-persistent` (0700); the retained
operator root is `/nix/var/nix/gcroots/dgx-setup-kms-persistent`. Recovery and
disable use that exact executable, even if the checkout later changes. Keep
the snapshot and root; neither is incidental cleanup material.

Selecting KMS does not select GNOME Wayland. Keep the initial rollout headless;
before enabling factory GDM with KMS loaded, implement and test its explicit
Xorg session policy. The boot fallback itself uses KMS off.

### Retrying the first menu-order failure

Use the same `enable --console-ready` command. It accepts the first attempt's
retained state only after proving that automatic recovery restored the exact
factory GRUB, neither old nor new managed link remains, and factory inputs
still match. An active, interrupted, unknown, or stale transaction is refused.
`check` can perform those retry checks without changing anything.

The retry preserves the old snapshot at
`/var/lib/dgx-setup/kms-persistent-before-menu-fix` and its executable at
`/nix/var/nix/gcroots/dgx-setup-kms-persistent-before-menu-fix`, then selects the
corrected operator and takes a new snapshot. It can resume after interruption
between those steps. Do not delete the state or roots to get past a collision.
The old output IDs in the code identify this specific recovered attempt, not
an upstream version pin or permission to migrate other live configurations.
See the [failure and regression record](../root/graphics/validation/2026-09-07-persistent-kms-menu-order.md).

## Current commands

```bash
./scripts/dgx-kms plan
./scripts/dgx-kms check
./scripts/dgx-kms status
```

These commands inspect only. `plan` reads the repository's policy.
`check` builds the small Nix-packaged inspector and its offline tests as the
normal user, then asks sudo to read protected boot configuration. It reports
the loaded KMS/fbdev booleans, factory override, GNOME policy, GRUB first-entry
kernel/initrd match, pending boot selections, storage compatibility clues,
and relevant unit states. It omits raw boot arguments, UUIDs, entry names,
environment values, and Tailscale identity.

`KMS_STATUS=BOOT_REVIEW_REQUIRED` means the inspection completed, not that
boot recovery or KMS has been tested. `reviewFindings` lists discrepancies to
resolve. An empty list is not permission to change or reboot the machine.
The one-boot arming operator below performs its own fresh checks. Persistent
configuration has a separate operator above; it is never implied by arming.

The tests use synthetic boot configuration and temporary filesystem trees.
They cover private-data filtering, EFI routing, entry preservation, failed
marker writes/readback, repeated entry selection, partial arming, cancellation,
foreign collisions, and clean retry. GRUB 2.12's real syntax checker parses the
generated test entry. Transaction tests use simulated writes and the real
`grub-editenv` utility against temporary files; they do not change the real
bootloader. Build them with
`nix build --no-link .#kms-preparation-policy`; run the repository checks with
`./scripts/dev check`. These tests do not exercise an actual KMS boot.
See the [tooling test record](../root/graphics/validation/2026-09-06-one-boot-trial-tooling.md)
for the exact artifacts and checks.

## First trial and recovery

The first trial is a separate GRUB entry for the **same factory kernel
and initramfs**, adding only `nvidia_drm.modeset=1`. Keep the usual entry and
its default selection unchanged. The operator copies the existing first entry's
body, preserving its disk and boot arguments, and refuses unsupported layouts.
It does not regenerate GRUB, create an initramfs, or copy another machine's
disk identifiers. The reviewed configuration hash and kernel in
`kms-plan.json` are pilot-specific inspection evidence, not fleet-wide defaults.

When independent keyboard/display/power recovery is available, this command
**changes the next boot selection, but does not reboot**:

```bash
./scripts/dgx-kms arm --console-ready
```

It verifies the current EFI boot entry, mounted EFI partition, Ubuntu forwarding
configuration, factory custom-entry hook, and absence of conflicting boot state.
It also reruns the original host preflight and the factory GRUB syntax checker.
It snapshots privately, retains the exact Nix recovery code, publishes a new
`/boot/grub/custom.cfg` without overwriting an existing file, and sets its trial
marker followed by `next_entry`. It preserves `grub.cfg`, `/etc/default/grub`,
all modprobe files, the normal default selection, and all root generations.

Do not run factory updates, another deployment, or bootloader maintenance while
the trial is armed. After a separately approved reboot, use `status` again.
`KMS_TEST_BOOT` requires a new boot, a consumed marker, a cleared selection,
unchanged normal GRUB configuration, and loaded `modeset=Y`. It is boot evidence,
not proof of working capture or healthy CUDA workloads.

To abandon the trial before reboot, or remove its boot entry after testing:

```bash
./scripts/dgx-kms cancel
```

Cancellation revokes the marker first, clears only this trial's selection, and
removes only its checksum-matching custom entry. It never overwrites unrelated
GRUB environment values. It does not unload KMS from the running kernel: if the
trial is running, KMS stays loaded until a later reboot. The original boot entry
still uses the factory setting. A canceled trial can be armed afresh; the prior
private snapshot is archived and its code root retained.

There is no confirmation phrase, countdown, automatic reboot, or silent
permanent enablement. Snapshots live under root-owned mode-0700
`/var/lib/dgx-setup/kms-trial` and `kms-trial-history`; they contain private boot
configuration and stay out of Git/Nix. An interrupted transaction can be
inspected with `status` and revoked with `cancel`. Unknown replacements are
preserved for review, not deleted.

GRUB can select an entry once and clear that selection before entering the
kernel. But its own `grub-reboot` helper warns that the selection can persist
when GRUB cannot write its environment block, including some LVM/RAID setups.
The original inspector only recognizes the expected header and storage clues.
The arming preflight additionally verifies EFI routing. Neither can prove a
future boot-time disk write. The trial therefore adds the KMS argument only if
GRUB successfully saves a unique marker as consumed and reads that value back.
A failed save/read, missing marker, or already-consumed marker leaves the
factory boot arguments in effect—even if the trial menu selection repeats.
These conditionals have algorithm and parser tests. The first pilot boot
confirmed successful marker consumption and KMS loading; failed marker I/O and
repeated-selection recovery have not been exercised on hardware. See the GNU documentation on
[environment storage](https://www.gnu.org/software/grub/manual/grub/html_node/Environment-block.html)
and [one-boot selection](https://www.gnu.org/software/grub/manual/grub/html_node/next_005fentry.html).

Independent console/power recovery must be available for the actual trial.
A userspace rollback timer cannot recover a kernel that hangs before systemd
starts, and a one-shot entry does not power-cycle a hung machine. A reboot is
separate from arming and is never performed by this operator. If boot hangs,
use local recovery to select the unchanged Ubuntu entry; do not depend solely
on an SSH connection or a userspace timer.

Keep the host in its existing headless mode for the initial KMS boot. Check
access and GPU compute first, then rerun the temporary Hyprland capture test.
Only after capture works should we advance to local GDM integration and actual
Sunshine/Moonlight streaming. Retest idle resource use and compute alongside
streaming; enabling a capability is not proof of 4K/120 performance.

The separate persistent adapter above preserves NVIDIA's driver/package and the vendor override
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
[Nix artifacts](../root/graphics/kms.nix) do not enter an active Home or System
Manager profile. The optional operator stages boot state only when invoked.

The matching kmod 31 [configuration reader](https://github.com/kmod-project/kmod/blob/v31/libkmod/libkmod-config.c)
parses the kernel command line after modprobe configuration files. Linux's
[module-option ordering documentation](https://www.kernel.org/doc/html/latest/admin-guide/dynamic-debug-howto.html#debug-messages-at-module-initialization-time)
describes the same precedence. This supports the one-boot override without
editing NVIDIA's file; the loaded sysfs value remains the real test result.
