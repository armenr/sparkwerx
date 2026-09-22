# Sunshine startup on the GB10

The operator reported a successful run of
`./scripts/test-remote-desktop-sunshine.sh` using commit `552554d`.
Its private snapshot is `20260906T205034Z-817cfd0f1386`; no raw log is published.

The exact test bundle was
`/nix/store/a1g93h9kw9k1axxah0vb3ac35spr4cm1-dgx-remote-desktop-sunshine-startup-test`,
using CUDA-enabled Sunshine 2026.516.143833 from
`/nix/store/3j2b6777c4i5kvikzw4ghfjz6qmfhafj-sunshine-2026.516.143833`.

The run passed:

- Temporary Hyprland with the 3840×2160, 120 Hz virtual-output preset and
  separate red/green pixel readback.
- Sunshine's Wayland display initialization and final H.264, HEVC, and AV1
  NVENC startup checks.
- Shutdown of Sunshine, the compositor, and the private seat broker.
- Host postflight: root profile, protected processes, access, files, and device
  permissions unchanged.

This validates the combined [CUDA build adapter](../../packages/sunshine/README.md),
[existing UVM exposure](2026-09-06-sunshine-uvm-device.md), and
[temporary DRM group access](2026-09-07-sunshine-drm-access.md).
No driver replacement, persistent group change, network listener, input access,
or desktop switch was needed. KMS was enabled for the separate test boot, not
permanently configured.

Sunshine's startup encoder probes use dummy images. The red/green readback
above uses Grim, not Sunshine. Changing frames through Sunshine's own capture
and encoder path are the next test; Moonlight streaming, input/audio, latency,
and sustained frame rate remain untested.
