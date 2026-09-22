# Sunshine's direct DRM-card access

CUDA initialization now succeeds. The next startup failure is in the test's
Unix group permissions: Sunshine opens the primary DRM card directly, but its
temporary process had only the render node's group.

## Evidence

The user reported snapshot `20260906T203333Z-bd6f011fa180` after the UVM fix in
`bd79b32`. The temporary unit stopped and host postflight passed. Its redacted
diagnostics reached Wayland display setup at 3840×2160, then reported:

```text
Error: Couldn't open DRM FD for CUDA device: Permission denied
```

In [Sunshine 2026.516.143833's CUDA implementation](https://github.com/LizardByte/Sunshine/blob/v2026.516.143833/src/platform/linux/cuda.cpp),
`open_drm_fd_for_cuda_device()` finds the CUDA device's primary `card*` node
through sysfs and calls `open(..., O_RDWR)`. It does not use the render node or
Hyprland's seatd connection. The error occurs before GBM/EGL device creation.

Read-only inspection of the actual pilot found:

| Node | Owner/group | Mode | Original temporary child access |
| --- | --- | --- | --- |
| `/dev/dri/card1` | root / video (44) | 0660; no extra ACL | Denied: no video membership |
| `/dev/dri/renderD128` | root / render (993) | 0660; no extra ACL | Allowed: render membership |

Both sysfs nodes identify the same NVIDIA GPU. Hyprland's successful readback
did not establish Sunshine's direct-card access: the root seatd broker opens
the card for Hyprland. The harness's `Popen(extra_groups=...)` supplied only
render membership to the normal-user process tree.

## Correction

- The Sunshine variant supplies the existing primary-card and render-node
  groups to its temporary child, using Python's
  [child-only `extra_groups` setting](https://docs.python.org/3.13/library/subprocess.html#subprocess.Popen).
  Capture-only still receives render membership alone.
- Group IDs come from root-owned, non-symlink character nodes with group
  read/write permission. They are not hard-coded or inherited from the caller.
- The unprivileged child checks its exact supplementary groups and DAC
  read/write access before starting Hyprland. That check opens no GPU device.
- No account, persistent membership, ACL, device mode, application capability,
  package source, driver, or desktop setting changes. The same device allowlist,
  hidden input/UVM-tools nodes, denied TCP/UDP, and 150-second deadline remain.
- After a failed run stops and passes host postflight, the wrapper automatically
  prints the existing inspector's redacted summary. Private-path validation and
  excerpt limits remain intact; a summary-read failure does not hide the test
  failure. Manual `inspect` remains available.

This is a harness fix, not a Sunshine source patch or a permanent graphics
permission policy. The [CUDA-enabled package](../../packages/sunshine/README.md)
and [UVM prerequisite](2026-09-06-sunshine-uvm-device.md) remain necessary.

## Validation

The focused capture suite passed 38 tests, including both factory-systemd syntax
checks without starting a unit. The broader remote-desktop suite passed 94 tests
with its optional Sunshine parser test skipped outside the Nix policy.
Both Nix session policies passed 68 tests and all three Hyprland configuration
parses. The capture-only policy skips Sunshine's parser; both policies skip the
factory systemd parser inside the Nix sandbox.

`./scripts/dev check` passed lint, documentation checks, its 149-test suite
(two optional parser checks skipped), and Nix evaluation. Sunshine's package
policy also passed; its compiled output is unchanged.

Built artifacts:

- Sunshine test: `/nix/store/a1g93h9kw9k1axxah0vb3ac35spr4cm1-dgx-remote-desktop-sunshine-startup-test`
- Sunshine session policy: `/nix/store/ndw61hvy5pfql3qxjzj04ga5d999jjxw-sparkwerx-private-session-policy`
- Capture-only test: `/nix/store/hy101xmp5qn500pimf7pbdpa3ipxslkw-dgx-remote-desktop-session-test`
- Capture-only policy: `/nix/store/01hydl2lhnridi36y229ay4vnlrh5yg2-sparkwerx-private-session-policy`

The read-only group selector returned `[993]` for capture-only and `[44, 993]`
for Sunshine on this host. The actual caller lacks card access, consistent
with its unchanged persistent memberships. No GPU was opened by that check.

The selected root generation remained
`/nix/store/djp7ap9gc7kq6c5hhbqzzslvmg4vq3m1-system-manager`. Expected headless
services remained active, GDM and Dashboard GUI remained inactive, and inspected
units had no pending daemon reload.

## Hardware retry

The revised full GPU test still needs the operator's sudo password:

```bash
./scripts/test-remote-desktop-sunshine.sh
```

A successful build does not establish later CUDA/GL interoperability, encoder
startup, changing-frame capture, streaming, or sustained FPS. The previously
reported startup result remains a failure until the revised hardware run passes.
