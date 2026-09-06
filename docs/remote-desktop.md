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
changing synthetic video with H.264, HEVC, and AV1 NVENC.
[Real Hyprland virtual-display readback also passed](../remote-desktop/validation/2026-09-06-temporary-capture-host.md)
during the KMS trial. These are working components, not yet a Sunshine stream.

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

## Temporary capture test on the pilot

Check the loaded NVIDIA DRM modesetting setting before attempting capture:

```bash
./scripts/test-remote-desktop-session.sh check-kms
```

This asks sudo only to read the current kernel parameter. It opens no GPU
device, starts no graphics or service, and changes no configuration.
`KMS_STATUS=DISABLED` stops this capture path; the test also checks it before
creating a snapshot or starting its transient service. `ENABLED` establishes
only this prerequisite, not successful capture.

The pilot has NVIDIA's `nvidia-drm-options-modeset0` package, which supplies
`/etc/modprobe.d/zz-nvidia-drm-override.conf` with `modeset=0`. The package file
is not proof of the current loaded value, so the check reads sysfs instead.
Do not delete that factory-owned file, purge its package, or reload GPU modules
to get past the test. Enabling KMS needs a separately reviewed, reversible
host configuration and boot plan while preserving the existing NVIDIA driver.
The [first optional KMS trial boot passed](../root/graphics/validation/2026-09-06-kms-test-boot.md),
and offscreen rendering/encoding plus temporary Hyprland capture passed with
KMS enabled. Factory GNOME/Xorg remains the alternate to local and
remote Hyprland. Use `./scripts/dgx-kms status` for the running trial; `check`
is the pre-arm inspection, not its postboot verifier. Neither command reboots.

This is a hardware diagnostic, not a remote-desktop installation. It needs
explicit permission to start temporary graphics and a sudo password, but no
local graphical login or confirmation phrase:

```bash
./scripts/test-remote-desktop-session.sh
```

The default is a 3840×2160 virtual output configured at 120 Hz. Pass `1440p120`
or `4k60` to test a smaller mode. The script currently accepts only the reviewed
`sparkle-01` headless generation five and its NVIDIA DRM card/render-node pair;
it is not a general fleet launcher.

It builds an immutable test bundle, snapshots protected host state, then starts
a uniquely named transient systemd service with a **150-second hard limit**.
The service has private `/run`, `/dev`, temporary files, and networking. Only
the NVIDIA graphics nodes are exposed; TCP/UDP socket creation and input-device
access are checked before the compositor starts. Host session/system D-Bus
sockets and user homes are hidden. A private root seatd broker handles DRM
access without a VT switch. Hyprland and its clients run as the normal user
with a temporary render-group membership and no effective capabilities.
The private runtime path is deliberately short enough for Hyprland's full
instance signature and Linux's Unix-socket pathname limit.

The test verifies the named virtual output, reads back red and green frames
through Grim, and checks Hyprland's log for the NVIDIA GB10 renderer. It stops
the compositor and broker, then compares the root profile, protected processes,
Tailscale identity/SSH health, configuration hashes, and GPU/input permissions
with the snapshot. Disconnecting cannot leave the test running indefinitely:
systemd kills the entire test process group at its deadline.

No package profile, boot link, user group, ACL, firewall rule, or normal desktop
mode changes. No Sunshine server, pairing, audio, or input injection starts.
The test does briefly access the **real shared GPU**; it is not a virtual GPU
test. Run it when no other graphical session or deployment guard is active.

Logs and before/after records stay root-owned under
`inventory/sparkle-01/raw/remote-desktop-session/`. Generated screenshots are
discarded. On failure, keep that evidence; don't relax device permissions or
activate a desktop just to make the test pass.

To inspect a failed attempt without restarting anything, pass the snapshot
name printed in its log path:

```bash
./scripts/test-remote-desktop-session.sh inspect 20260906T135057Z-b9a45dfe19c3
```

This uses sudo only to read the root-private log and prints redacted wrapper,
compositor, and seat-broker diagnostics, including native crash messages.
It does not print the raw log, change file permissions, or rerun the GPU test.

Grim 1.5.0 uses the compositor's image-copy protocol when available, otherwise
wlr-screencopy. Neither is Sunshine's wlr-export-dmabuf capture path. A pass
therefore proves this temporary compositor/readback path, **not sustained
120 FPS, Sunshine streaming, or Moonlight performance**. The
[4k120-preset hardware run passed](../remote-desktop/validation/2026-09-06-temporary-capture-host.md);
the earlier [preparation record](../remote-desktop/validation/2026-09-06-temporary-capture-preparation.md)
documents its construction and isolation checks.

## Temporary Sunshine startup test

The [first hardware attempt](../remote-desktop/validation/2026-09-06-sunshine-startup-failure.md)
found the virtual display but failed encoder initialization. The locked stock
Sunshine build disables CUDA, which removes its Wayland CUDA/GL encoder device.
The front door rejects CUDA-disabled builds before sudo or a GPU session.
The approved [Nix adapter](../packages/sunshine/README.md) enables that code and
preserves the temporary session's factory-driver library path. Its isolated
package set permits the required CUDA compiler, runtime, and CCCL headers;
factory CUDA and the driver remain unchanged.
The [CUDA build and package checks passed](../remote-desktop/validation/2026-09-06-sunshine-cuda-build.md).
Its [next hardware attempt identified a harness omission](../remote-desktop/validation/2026-09-06-sunshine-uvm-device.md):
CUDA initialization needs the existing `/dev/nvidia-uvm` node. The Sunshine
variant now exposes that one additional GPU device; capture-only does not.
Both still hide `/dev/nvidia-uvm-tools`. The full corrected startup test needs
a rerun; no driver or Sunshine source patch is indicated by this failure.

Run the diagnostic as the normal user. It builds and checks the CUDA-enabled
package first, then requests sudo for the same temporary GPU session:

```bash
./scripts/test-remote-desktop-sunshine.sh
```

It repeats the virtual-display/red-green readback checks, then starts the
CUDA-enabled Sunshine 2026.516.143833 package inside that private session.
It requires Sunshine's Wayland display initialization at the expected dimensions
and its final H.264, HEVC, and AV1 NVENC success messages, then stops Sunshine,
Hyprland, and seatd. `1440p120` and `4k60` are also accepted.

The whole service still has a 150-second hard limit, and Sunshine gets at most
60 seconds of startup time. Input devices and TCP/UDP remain denied. Audio,
tray, UPnP, and display reconfiguration are disabled; the application list is
empty. Homes and host D-Bus sockets stay hidden. Application state and logs are
private, with no profile install, listener exposure, persistent service, device
permission, desktop switch, or reboot. The wrapper repeats the same protected
host postflight before reporting success.

UVM must already be provided by the factory driver. The test checks the node's
type, owner, and current driver device number before launch and inside the
private session; it never creates nodes, changes host permissions, or loads
modules to satisfy that prerequisite. Host postflight also checks both UVM
nodes' metadata.

This is deliberately a **startup** test. In the pinned
[encoder probe](https://github.com/LizardByte/Sunshine/blob/v2026.516.143833/src/video.cpp),
Sunshine initializes the selected display and tests encoding dummy images.
It uses its own 1080p/60 encoder-test configuration, not the virtual output's
4k120 mode as a performance test. The
[Wayland backend](https://github.com/LizardByte/Sunshine/blob/v2026.516.143833/src/platform/linux/wlgrab.cpp)
fetches actual display frames in its separate capture loop. A startup PASS
therefore does not establish Sunshine changing-frame capture or throughput.

The [startup sequence](https://github.com/LizardByte/Sunshine/blob/v2026.516.143833/src/main.cpp)
probes encoders before starting the streaming/admin listeners. The diagnostic
can recognize that stage even if the process then exits on denied sockets;
exit code alone is never success. Those socket failures are expected in this
test, not a reason to loosen its isolation. A working server and Moonlight
stream need a separate transport test.

On failure, inspect the snapshot name printed by the wrapper:

```text
./scripts/test-remote-desktop-sunshine.sh inspect SNAPSHOT_NAME
```

The shared inspector prints redacted Sunshine/backend/encoder diagnostics,
not the raw private log. It keeps the first and last 20 relevant Sunshine lines
when there are more than 40, with an omitted-line count, so fallback errors don't
hide the initial failure. It also reports when only the last MiB of the private
log was read. Inspection stays available even when the package check rejects a
GPU retry. The [offline preparation checks](../remote-desktop/validation/2026-09-06-sunshine-startup-preparation.md)
and [failed hardware attempt](../remote-desktop/validation/2026-09-06-sunshine-startup-failure.md)
are separate records; neither changes the earlier capture-only PASS or
authorizes another reboot.

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
- Carry the tested temporary NVIDIA DRM/GBM/EGL bridge into a reviewed session
  lifecycle, and verify Sunshine's actual changing-frame capture/encode path.
  The temporary broker is not a permanent device-permission policy.
- Scope input, audio, and session startup/shutdown. Do not grant blanket input
  access or `CAP_SYS_ADMIN` as a shortcut.
- Implement guard-before-listener ordering, rollback, tailnet-loss handling,
  headless shutdown, and unwanted LAN-discovery prevention.
- Provision credentials privately, pair a client, and measure the stream.
  Include reconnect, an explicitly authorized reboot, and return to compute-only
  headless without losing Tailscale SSH.

GNOME RDP is only a possible setup/recovery aid, not an additional default.

## Updates and references

Sunshine uses the existing locked `nixpkgs-apps` source with a small
[build-option and wrapper adapter](../packages/sunshine/README.md), not a
handwritten version override. Follow that recipe's update checks, including
its CUDA toolchain and runtime-closure checks. Compare with the latest **stable** release, not daily
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
