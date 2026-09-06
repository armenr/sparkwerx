# NVIDIA rendering, encoding, and virtual-session preparation

On sparkle-01, the Nix-built test programs used the existing GB10 driver
580.173.02 successfully. No desktop, listener, service, user-group change, or
reboot was needed.

## Hardware results

The EGL test created a private 16×16 pbuffer through Nix GLVND and the factory
NVIDIA EGL driver. It required an NVIDIA renderer and verified red and green
pixel readback. This is offscreen rendering, not a Wayland/GBM capture test.

The NVENC matrix used the locked apps lane's FFmpeg 9.0.1:

| Input preset | H.264 | HEVC | AV1 |
| --- | --- | --- | --- |
| 1280×720, 30 FPS metadata | Pass | Pass | Pass |
| 2560×1440, 120 FPS metadata | Pass | Pass | Pass |
| 3840×2160, 60 FPS metadata | Pass | Pass | Pass |
| 3840×2160, 120 FPS metadata | Pass | Pass | Pass |

Each entry is a short 60-frame synthetic encode with an explicit NVENC encoder,
followed by decoding, exact metadata/count checks, and changing-frame checksum
checks. There is no software-encoder fallback. These passes do **not** establish
sustained frame rate, capture quality, Moonlight decoding, or Sunshine's own
bundled-FFmpeg path.

The final matrix was rerun after adding private driver-cache behavior and
failure-path tests. Every run compared the protected service records and
selected System Manager profile before/after; all matched. Successful temporary
test directories were removed. Driver libraries remained factory-owned.

## Session preparation

Fourteen offline GPU-runner tests cover metadata, driver-library selection,
cache/loader isolation, encoder failures, timeouts, postflight failures, and
private diagnostic retention. Twelve fake-compositor tests cover explicit
instance/PID matching, refusal to adopt existing outputs, exact modes, finite
startup deadlines, interruption, and cleanup that never targets a replacement
process.

The pinned Hyprland 0.56.2 also accepted all three generated configurations
using `--verify-config` inside a Nix build. That command does not launch the
compositor. The configuration disables physical outputs and names one virtual
output, `SPARKWERX-REMOTE`; no application, portal, or Sunshine autostart is
included. A future dedicated-session supervisor must create and verify that
output before starting clients.

The [locked Aquamarine backend](https://github.com/hyprwm/aquamarine/blob/1a10fe26a9f7d989c359e6a9ea61aa2e44d06c36/src/backend/Backend.cpp#L148)
needs a DRM-backed allocator; its
[headless backend](https://github.com/hyprwm/aquamarine/blob/1a10fe26a9f7d989c359e6a9ea61aa2e44d06c36/src/backend/Headless.cpp#L122)
does not supply a DRM file descriptor on its own. Therefore virtual-output
support is not proof that Hyprland can start without a DRM-capable session.
The current SSH user cannot access the NVIDIA card/render nodes or `/dev/uinput`,
and unattended sudo is unavailable. No permissions were changed to bypass this.

Next: a separately scoped temporary graphical-session test with the necessary
device access, then changing-frame capture and Sunshine encoding. It can be
operated over SSH; a physical monitor is not a prerequisite for preparing it.
Keep ports closed and input unavailable until their corresponding tests.

## Reproduce

```bash
./scripts/test-remote-desktop-graphics.sh
```

This runs the offline/configuration builds and the complete hardware matrix.
It does not start Hyprland or Sunshine. See the
[remote-desktop guide](../../docs/remote-desktop.md) for individual preset tests.

## Exact artifacts

These results use the implementation developed on top of
`16c214bc6bdc1d0cf4c47cc3ea6bce7b9e98beb2`; the following store identities pin
the tested code independently of the documentation commit.

| Artifact | Store output |
| --- | --- |
| Hardware test bundle | `/nix/store/kknrh29x501yjp8nv5vsnbvf7r4cc550-dgx-remote-desktop-gpu-test` |
| GPU policy tests | `/nix/store/mhqql28cdf7kah9d7qd3qdjr8vqi5lc6-sparkwerx-remote-desktop-gpu-policy` |
| Virtual-session tests/configs | `/nix/store/gqglanlj1gb1xk3mkazk19vszb7dg1m0-sparkwerx-remote-desktop-session-policy` |
| FFmpeg binary | `/nix/store/ply7yv3ijxd39y1v23y63nc78d3a2ww6-ffmpeg-headless-9.0.1-bin` |

The pilot remained on generation five, headless, with Nix-owned Tailscale
active and GDM/Dashboard GUI inactive. No pending reload appeared on the checked
units. No Home/root profile, package pin, firewall, Tailscale state, or persistent
graphics configuration was changed by this work.
