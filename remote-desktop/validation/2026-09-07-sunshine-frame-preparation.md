# Offline Sunshine frame-test preparation

The [startup hardware test passed](2026-09-07-sunshine-startup-host.md).
This next diagnostic tests changing-frame capture and encoding separately,
without network transport or a persistent session.

## Implementation

The [separate Nix derivation](../../packages/sunshine/capture-test.nix) uses
Sunshine 2026.516.143833 with the already approved CUDA recipe and replaces
only the application entry point. Checksums retain the original video engine,
Wayland capture, CUDA code, and OpenGL conversion implementation. Its original
runtime shaders are included and compared against the source during installation.
The normal Sunshine package is unchanged.

The entry point calls `video::probe_encoders()` and `video::capture()` directly.
It saves elementary video packets before transport, applying the upstream
transport's first-match payload-replacement semantics. It does not initialize
HTTP, RTSP, audio, input, display reconfiguration, or application launchers.
It installs no server command, service, udev rule, or desktop launcher.

The [Python verifier](../sunshine-frames.py) changes the synthetic client between
red and green, checks capture timestamps and packet ordering, and decodes each
codec locally with the existing FFmpeg dependency. It requires full-resolution
codec metadata, matching encoded/decoded counts, and at least three decoded
red/green transitions. Generated videos are removed after the test; counters
and redacted failure diagnostics remain available through the private log.

The existing service retains its 150-second limit, private network with IP
sockets denied, hidden input devices, temporary card/render groups, and full
host postflight. No permission, package selection, dependency pin, service,
desktop, boot, or KMS change is part of this work.

## Built and checked

- Diagnostic binary: `/nix/store/j8rk6n3iy54428nw9f0xfml1dlccp4si-sparkwerx-sunshine-capture-2026.516.143833`
- Hardware-test wrapper: `/nix/store/bhb4pay8ban7lp9idlqam651c3lyn5by-dgx-remote-desktop-sunshine-frames-test`
- Frame-test policy: `/nix/store/k687bry3q28nl87xiaa840w6r5w9b4px-sparkwerx-private-session-policy`
- Normal Sunshine, unchanged: `/nix/store/3j2b6777c4i5kvikzw4ghfjz6qmfhafj-sunshine-2026.516.143833`

The package build checked the CUDA flags, compiled objects, defined CUDA/GL
encoder factory, unchanged engine source, installed shaders, and inert
`--describe` command. Calling its capture mode outside the private work directory
was rejected before graphics initialization.

The frame-test policy passed 76 tests, with only the factory-systemd parser
skipped in the build sandbox. CPU-generated H.264, HEVC, and AV1 clips each
decoded to 32 frames, 16 red and 16 green, with three transitions. Incorrect
frame counts were rejected. Other tests reject static/dummy images, a single
color transition, missing capture timestamps, incorrect modes/codecs, and
invalid metadata. All three Hyprland preset configurations parsed successfully.
The original capture-only and Sunshine-startup policies also passed.

`./scripts/dev check` passed lint, documentation validation, 157 unit tests
(three optional checks skipped outside their Nix policy), and flake evaluation.
The shader files also match those in the unchanged production package.

## Hardware test still needed

No GPU session was run while preparing this executable. Read-only host checks
still found headless generation five selected, healthy systemd/Tailscale/factory
services, inactive GDM/Dashboard GUI, and no pending daemon reload on inspected
units. The operator's sudo password is needed for:

```bash
./scripts/test-remote-desktop-sunshine-frames.sh
```

This test cannot establish Moonlight transport, input/audio, latency, or
sustained FPS. Its [contract](../../docs/remote-desktop.md#temporary-sunshine-changing-frame-test)
keeps those results separate.
