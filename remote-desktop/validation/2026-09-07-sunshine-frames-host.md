# Sunshine changing-frame capture on the GB10

The operator reported a successful
`./scripts/test-remote-desktop-sunshine-frames.sh` run using commit `a6849f0`.
The private snapshot is `20260906T212121Z-6281e8acace2`. No private log or video
is published here.

## What passed

- Temporary Hyprland at the 3840×2160, 120 Hz virtual-output preset, with
  separate Grim red/green pixel readback.
- Sunshine's actual Wayland capture, CUDA conversion, and NVENC encoding path,
  exercised through the separate offline diagnostic entry point.
- Locally decoded H.264, HEVC, and AV1 video containing repeated red/green
  changes. The verifier also requires the requested full-resolution dimensions,
  ordered packets, multiple capture timestamps, and matching decoded frame counts.
- Shutdown of the diagnostic, compositor, and private seat broker.
- Host postflight: root profile, protected processes, access, files, and device
  permissions unchanged.

The [preparation record](2026-09-07-sunshine-frame-preparation.md) identifies the
exact build and verification logic:

| Artifact | Store output |
| --- | --- |
| Hardware-test wrapper | `/nix/store/bhb4pay8ban7lp9idlqam651c3lyn5by-dgx-remote-desktop-sunshine-frames-test` |
| Offline capture executable | `/nix/store/j8rk6n3iy54428nw9f0xfml1dlccp4si-sparkwerx-sunshine-capture-2026.516.143833` |
| Frame-test policy | `/nix/store/k687bry3q28nl87xiaa840w6r5w9b4px-sparkwerx-private-session-policy` |

This closes the gap left by Sunshine's startup-only dummy-image probes. The
diagnostic retains the original capture, conversion, and encoder source;
its separate entry point omits network transport, audio, and input.

The run kept the 150-second service limit and denied TCP/UDP and input access.
It did not install a profile, start a persistent server, change desktop mode,
reboot, or make KMS permanent. KMS remains part of the separately authorized
test boot.

## Remaining proof

This was a short capture/encode/decode test at the **requested** 4k120 preset,
not evidence of sustained 120 FPS or a usable Moonlight connection. No client
was paired. Transport, interactive keyboard/mouse input, audio, latency,
reconnect behavior, and sustained performance still need their own results.

The next useful test is a temporary Tailscale-only Moonlight session. That
crosses the existing diagnostic's network/input boundary and needs a separately
reviewed launcher, cleanup behavior, and explicit operator scope. Do not loosen
the passed offline test or turn it into a persistent desktop deployment.
