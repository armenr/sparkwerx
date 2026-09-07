# Try Moonlight from a MacBook

[Remote desktop](remote-desktop.md) · [Current status](status.md)

This is a 30-minute private Hyprland/Sunshine session on `sparkle-01`, not a
permanent desktop installation. It shows an animated test screen with mouse
and keyboard counters. Your regular home directory stays hidden from it.
Audio, clipboard text injection, touch, pen, and gamepads are not enabled.

The launcher builds and passes its CPU/package checks. Its new privileged
container lifecycle and first client connection still need to run. `start`
runs that exact container test first; failure prevents a live launch.

## Get the Mac ready first

Install the **macOS Universal** download from the
[official Moonlight release](https://github.com/moonlight-stream/moonlight-qt/releases/latest).
Keep Tailscale connected to the same tailnet as the Spark. No router port
forwarding, public sharing, UPnP, or additional server installation is needed.

Start with Moonlight set to **3840×2160, 60 FPS, 60 Mbps, automatic codec,
HDR off**. This is an initial setting, not a measured performance result.
Do not change macOS network or security settings to chase performance yet.

## Start on the Spark

In your existing SSH terminal:

```bash
cd ~/Development/DGX-setup
./scripts/dgx-moonlight-trial start 4k60
```

This builds the launcher and test fixtures before requesting sudo, runs the
disposable network/lifecycle checks, checks the real host stayed unchanged,
then starts the temporary session. Nothing
listens on the real host unless the container test passes. Preparation time
does not consume the 30-minute session limit.

Check startup:

```bash
./scripts/dgx-moonlight-trial status
```

Wait for `TRIAL_STATUS=READY_FOR_PAIRING`. If it stops or reports a failure,
use `./scripts/dgx-moonlight-trial inspect` for a redacted summary of the latest
trial. Do not paste raw logs or pairing credentials into an issue or chat.
`./scripts/dgx-moonlight-trial test` runs only the container gate and host checks.

## Open Sunshine administration through SSH

In a **new Terminal window on the Mac**, run:

```bash
trial_ip="$(ssh n0b0dy@sparkle-01 /usr/bin/tailscale ip -4)"
ssh -t -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 \
  -L "127.0.0.1:47990:${trial_ip}:47990" n0b0dy@sparkle-01
```

Leave this SSH shell open. The address stays in a local shell variable rather
than this repository. Use ordinary `ssh` here: `-L` is an OpenSSH option, not
a `tailscale ssh` option. The normal SSH session also completes the Tailscale
SSH authorization path used by local forwarding. Keep host-key checks enabled.
If forwarding is refused by the tailnet policy, inspect that policy; don't
open the administration port to the LAN or tailnet as a workaround.

On the Mac, open [https://localhost:47990](https://localhost:47990). Sunshine
uses a self-signed certificate. Accept that warning only for this intended
local tunnel, then create a temporary username/password in the page.

In Moonlight, add `sparkle-01` manually. Click it to pair, and enter Moonlight's
PIN in Sunshine's **PIN** page. Keep the PIN and credentials out of chat.
Launch **Private test screen**.

## What to check

- The orange bar moves and the picture stays clean for several minutes.
- The pink cross follows your pointer; clicks, typing, and scrolling advance
  the corresponding counters. The screen does not record what you type.
- **Control–Option–Shift–S** opens Moonlight's performance overlay on macOS.
  Note the selected codec, received FPS, decode/network latency, and dropped
  frames. A configured 120 Hz output is not proof of 120 FPS streaming.
- Disconnect and reconnect once while the trial is still running.

Report the Mac model/chip, Moonlight settings, observed statistics, and whether
input/reconnection worked. Audio being absent is expected for this trial.
The setup and shortcuts follow the
[Moonlight client guide](https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide).

After a working baseline, restart with `1440p120` or `4k120` and match that mode
in Moonlight. Check the Mac's display/decoder capability before judging 120 FPS.

## Stop and cleanup

On the Spark:

```bash
./scripts/dgx-moonlight-trial stop
```

The session also stops automatically within 30 minutes. Disconnecting SSH does
not cancel that deadline. No confirmation phrase or manual timer cancellation
is needed. Stop or exit the Mac's tunnel shell when finished.

The controller stops the whole graphics worker before removing only its own
firewall table. Pairing credentials and certificates disappear with its private
runtime storage. A new trial needs fresh pairing; remove the old Moonlight
entry if its saved certificate gets in the way.

Root-private logs and before/after checks remain under
`inventory/sparkle-01/raw/moonlight-trial/`. If a firewall rule or protected host
state changes unexpectedly, the graphics worker is stopped and evidence is
kept for inspection. Use `status`, `inspect`, and `stop`; don't delete state or
flush firewall rules manually.

## For maintainers

The [controller](../remote-desktop/trial-control.py) owns two transient services:
a guardian with a 30-minute systemd deadline and an isolated GPU worker tied to
it with `BindsTo`/`After`. `ExecStopPost` handles normal exit, timeout, and a killed
guardian. The [container test](../remote-desktop/trial-lifecycle-test.nix) uses the
same controller with a separate, container-only echo-server fixture and a shorter
deadline. It runs the actual JSON firewall transaction through 32 IPv4/IPv6
probes, then exercises stop, crash, failure, access loss, changed-rule handling,
and the systemd deadline with a deliberately suspended guardian.
These are not GPU, client, or sustained-FPS tests.

Every trial Python entrypoint uses `-B`, including detached children. Root can
otherwise write `__pycache__` into a Nix output despite its read-only file modes.
Build each source tree from the explicit file list in
[`trial.nix`](../remote-desktop/trial.nix); do not recursively copy a previously
executed output. The container test verifies the source hashes after root-run
imports. See the [source-cache fix](../remote-desktop/validation/2026-09-07-moonlight-source-cache.md).

Sunshine binds the runtime-verified Tailscale IPv4 address. The dedicated
`inet sparkwerx_sunshine` input chain drops ordinary-LAN traffic for both IP
families and permits TCP 47990 only through loopback. It neither flushes nor
replaces Docker/Tailscale rules. It does not change tailnet grants.

The [private GPU worker](../remote-desktop/trial-session.py) reuses the passed
driver bridge, existing device nodes, and child-only card/render groups.
Physical input, `/dev/uinput`, host homes, and host D-Bus remain hidden; the
graphics processes run as the normal user with zero effective capabilities.
It does not update a root/Home profile, switch normal desktop mode, alter KMS
or boot settings, restart Tailscale, or reboot. The original 150-second offline
diagnostic sources and outputs remain unchanged.
