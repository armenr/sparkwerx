# Remote desktop over Tailscale

[Desktop modes](desktop-modes.md) · [Configuration](configuration.md)

The selected stack is **Sunshine on the Spark, Moonlight on your client**, over
Tailscale: high-resolution, high-frame-rate streaming for editing, visualization,
and interactive AI work. It is optional, not part of the base CLI package set.

The repository provides a Nix package candidate, configuration/network templates,
client presets, and a read-only prerequisite check. There is **no activation
command yet**. Selecting it does not install Sunshine, start graphics, or open
ports. Capture, input/audio, and the service lifecycle still need testing.

The [package and isolated network tests passed](../remote-desktop/validation/2026-09-06-preparation.md).
They verify the firewall's packet behavior, not a working graphical stream.
The [GPU tests also passed](../remote-desktop/validation/2026-09-06-gpu-and-session-preparation.md):
Nix programs rendered offscreen through the factory NVIDIA driver and encoded
changing synthetic video with H.264, HEVC, and AV1 NVENC. A Sunshine stream is
the next integration step, not an outcome of those tests.

## Selection

Add this under a host's `desktop` object in `fleet/hosts.json`:

```json
{
  "remoteDesktop": {
    "selected": true,
    "backend": "sunshine",
    "transport": "tailscale",
    "clientPreset": "1440p120"
  }
}
```

Omitting it defaults to off. Tailscale must also be selected. Inspect without
changing the machine:

```bash
./scripts/dgx-remote-desktop plan
./scripts/dgx-remote-desktop check
```

Build the preparation artifacts and test the network rules (sudo is used only
for disposable network namespaces, not host configuration):

```bash
./scripts/test-remote-desktop-preparation.sh
```

In `headless` mode this selection is dormant. “No monitor attached” is different:
streaming still needs a running compositor and a capturable display, real or
virtual. A headless apply must not start a graphical session for this role.

## Without a monitor

The target is a remote desktop that needs only power and networking at the
Spark: no physical monitor, no HDMI dummy plug, and no local graphical login
before connecting after a reboot. Prefer a software virtual display.

The first candidate to test is Hyprland's virtual output with Sunshine's `wlr`
capture and NVIDIA NVENC encoding. The pinned
[Hyprland 0.56.2 output implementation](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/debug/HyprCtl.cpp#L1632)
includes virtual-output creation, and the pinned
[Sunshine capture documentation](https://github.com/LizardByte/Sunshine/blob/v2026.516.143833/docs/configuration.md#capture)
explicitly describes capturing Hyprland virtual displays. These are the
building blocks, not proof of a complete monitor-free session on GB10.

Create and verify the virtual display before starting capture or applications;
do not depend on a pre-existing local desktop. There are upstream
[reports of black capture after disabling the last physical display](https://github.com/hyprwm/Hyprland/discussions/14616).
They are not evidence that our pin fails, but they make monitor-free startup
and continuous changing-frame capture essential tests.

Keep two distinct operating states: a graphical mode may run the virtual
desktop and Sunshine; compute-only `headless` stops both while keeping
Tailscale and compute available. Switching modes remains an explicit operation,
not a side effect of connecting a Moonlight client. Monitor-free Hyprland does
not establish monitor-free GNOME or KDE support.

## Clients

The client targets are **MacBooks running macOS, Linux PCs, and Windows PCs**.
[Moonlight PC](https://github.com/moonlight-stream/moonlight-qt#downloads)
supports all three, including hardware-accelerated video decoding.

Each client runs Moonlight and Tailscale; Sunshine runs on the Spark. The server
role stays the same across client operating systems. Client installation is
separate from Spark provisioning: Moonlight does not enter the Spark's base
profile.

Choose the [quality preset](#quality-targets) for the actual client's display,
refresh rate, and hardware decoder, not just its OS. Verify those capabilities
on each device before targeting 120 FPS or choosing HEVC/AV1. Keep HDR off for
the initial stream tests.

## Graphics checks without a desktop

Run as your normal user; no sudo or monitor is needed:

```bash
./scripts/test-remote-desktop-graphics.sh
```

This builds temporary test tools in the Nix store, checks the three virtual
display configurations with the pinned Hyprland parser, and tests offscreen
rendering plus all three NVENC codecs at each quality preset. It generates its
own video, briefly uses the GPU, and opens no window or network listener.
Protected services and the selected root profile must match before and after.
Successful runs remove their temporary data; failures retain private diagnostics.

For a shorter check or one preset:

```bash
./scripts/test-remote-desktop-gpu.sh
./scripts/test-remote-desktop-gpu.sh --preset 4k60 --codec hevc
```

Each codec test encodes and decodes 60 frames and checks codec, dimensions,
frame-rate metadata, frame count, and changing content. **This is not a sustained
FPS benchmark.** Sunshine bundles different FFmpeg build inputs, so its own
capture/encode path still needs an end-to-end test.

The driver bridge exposes only reviewed factory NVIDIA libraries in a private
directory. It neither replaces the driver nor adds all of Ubuntu's libraries
to a Nix process. Shader caches are disabled for the test.

The virtual-display helper is preparatory code, not a session launcher. Its
tests reject another compositor's PID, existing outputs, invalid modes, and
startup timeouts. The pinned compositor accepts the rendered configurations;
no real virtual output has been created by these checks.

## Private access

Manually add the Spark's Tailscale address or MagicDNS name in Moonlight. No
router port forwarding, UPnP, Funnel, or ordinary LAN access is part of this role.

| Purpose | Ports | Intended access |
| --- | --- | --- |
| Pairing / session negotiation | TCP 47984, 47989, 48010 | Tailscale only |
| Video / control / audio | UDP 47998–48000 | Tailscale only |
| Sunshine administration | TCP 47990 | Local SSH forward over Tailscale only |

The design combines a runtime-resolved Tailscale bind address with a separate
`inet sparkwerx_sunshine` firewall table. The table drops outside traffic for
IPv4 and IPv6 without replacing Docker/Tailscale rules or opening other
firewalls. Direct tailnet access to the admin port is blocked too.

The SSH forward targets the server's own Tailscale address. That locally
forwarded connection can have a non-loopback source address, so the template
uses `origin_web_ui_allowed = wan`. This is an application setting, **not a
network permission**. Never run the template without its network guard.

Keep Sunshine authentication and Moonlight pairing. Credentials, certificates,
pairing state, addresses, and logs belong outside Git and the Nix store.
Tailnet grants should permit only the intended clients and streaming ports;
adding a narrow grant does not undo an existing broad allow rule. Sparkwerx
does not silently edit your tailnet policy.

## Quality targets

These are starting points to set in Moonlight, not measured Spark performance
or Sunshine server-side resolution commands:

| Preset | Resolution / frame rate | Starting bitrate |
| --- | --- | --- |
| `1440p120` | 2560×1440 at 120 FPS | 40 Mbps |
| `4k60` | 3840×2160 at 60 FPS | 60 Mbps |
| `4k120` | 3840×2160 at 120 FPS | 100 Mbps |

Start with 1440p120 or 4k60, HDR off. Attempt 4k120 after checking the client
display/decoder, capture path, encode latency, dropped frames, and network.
The template requires NVENC, with no silent CPU-encoding fallback. Codec
advertisement follows encoder capabilities rather than forcing HEVC or AV1.
The factory NVIDIA driver stays in charge.

Check that Tailscale has a direct peer connection and use Moonlight's stream
statistics. DERP remains encrypted but can add latency or limit throughput.
Retest while a representative GPU workload runs; reduce bitrate before
changing global network settings.

## Before deployment

- Finish the repeatable guarded desktop transition while preserving SSH.
- Test a cold start with no physical display or local graphical login, then
  verify changing frames from the intended virtual output. Sunshine's `wlr`
  capture is not a GNOME capture backend.
- Extend the proven offscreen/encoder bridge to Hyprland's DRM/GBM and
  Sunshine's capture/encode path. The SSH user currently lacks access to the
  NVIDIA DRM nodes; the pbuffer test does not exercise that permission path.
- Scope input, audio, and session startup/shutdown. Do not grant blanket input
  access or `CAP_SYS_ADMIN` as a shortcut.
- Implement guard-before-listener ordering, rollback, tailnet-loss handling,
  headless shutdown, and unwanted LAN-discovery prevention.
- Provision credentials privately, pair a client, and measure the stream.
  Include reconnect, an explicitly authorized reboot, and return to compute-only
  headless without losing Tailscale SSH.

GNOME RDP is only a possible setup/recovery aid, not an additional default.

## Updates and references

Sunshine uses the existing locked `nixpkgs-apps` package, not a handwritten
version override. Compare with the latest **stable** release, not daily
prereleases or a moving documentation version. Review capture, ports, settings,
bundled FFmpeg, and input permissions before updating. Rebuild and retest before
activation. Moonlight belongs on the client, not every Spark's base.

- [Sunshine stable releases](https://github.com/LizardByte/Sunshine/releases/latest)
- [Versioned Sunshine settings](https://github.com/LizardByte/Sunshine/blob/v2026.516.143833/docs/configuration.md)
- [Sunshine capture prerequisites](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2getting__started.html)
- [Moonlight clients and setup](https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide)
- [Spark hardware specifications](https://docs.nvidia.com/dgx/dgx-spark/hardware.html)
- [Tailscale connection types](https://tailscale.com/docs/reference/connection-types)
- [Tailscale grants](https://tailscale.com/docs/reference/syntax/grants)
