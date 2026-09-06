# Temporary Hyprland capture test preparation

The operator authorized a short-lived GPU/capture test over SSH, without
listeners, reboot, or a permanent desktop transition. The live pilot remained
on headless generation five while this diagnostic was developed.

## Implemented

- Immutable Nix test bundle and one normal-user front door:
  `scripts/test-remote-desktop-session.sh`; sudo is requested only for the test.
- Private transient service with a 150-second runtime limit, five-second stop
  limit, whole-process-group cleanup, no restart, and no boot installation.
- Private `/run`, `/dev`, network namespace, temporary files, and hidden homes.
  GPU nodes are explicitly allowed; input, TTY switching, and host session IPC
  are unavailable. Startup probes require IPv4/IPv6 TCP/UDP socket creation to
  fail before launching the compositor.
- Root seatd broker in that private namespace. Its capability set supports
  device opening, ownership/UID changes, cleanup, and DRM-master operations;
  it is not a system-wide seat service or a capability grant to Sunshine.
  The compositor/client process has no effective capabilities and receives only
  the render group for the lifetime of this test.
- Factory NVIDIA-only EGL/GBM bridge; no replacement driver or blanket Ubuntu
  library search path. The independently versioned EGL GBM platform is checked
  for trusted ownership and AArch64 ELF format, not confused with the NVIDIA
  driver's version number.
- Explicit child PID/IPC ownership, virtual-output size/rate validation, a
  compiled SHM color client, RGB readback, and NVIDIA GB10 renderer verification.
- Private logs, exact protected-host before/after checks, and no retained
  screenshots. No profile, group, ACL, desktop, firewall, or boot changes.

## Validation

The initial 18 offline tests pass, including the factory systemd 255 unit
parser. The color client compiles with warnings treated as errors. The Nix
policy check also validates each test configuration with pinned Hyprland's
parser. These checks do not start a compositor or a host service.

`./scripts/dev check` passed: repository lint, documentation checks, 60 Python
tests (one optional test skipped), snapshot-parser regression, and Nix
evaluation. Compared with main commit
`fd5cf97b50dacac4692f270aeb76cd6acd4b6d5d`, all 27 existing package derivations
and all 43 existing check derivations stayed identical. Only two test packages
and one check were added; existing root/Desktop/Tailscale artifacts did not move.

**The privileged hardware test has not run.** Noninteractive sudo requires a
password. Run the front door from the pilot's normal SSH shell and record its
actual result separately. If it fails, inspect the private log rather than
reclassifying the preparation checks as capture proof.

## Source details checked

- [seatd 0.9.3 socket setup](https://github.com/kennylevinsen/seatd/blob/0.9.3/seatd/seatd.c):
  the broker uses a compile-time `/run/seatd.sock`; `SEATD_SOCK` selects the
  client socket, not the broker's bind path. The private `/run` isolates both.
- [seatd's VT setting](https://github.com/kennylevinsen/seatd/blob/0.9.3/seatd/server.c):
  `SEATD_VTBOUND=0` disables VT binding for this broker.
- [seatd DRM-master ioctls](https://github.com/kennylevinsen/seatd/blob/0.9.3/common/drm.c).
- [Hyprland instance inventory](https://github.com/hyprwm/Hyprland/blob/v0.56.2/hyprctl/src/main.cpp)
  supplies the explicit child PID, instance signature, and Wayland socket.
- [Grim 1.5.0 capture selection](https://gitlab.freedesktop.org/emersion/grim/-/blob/v1.5.0/main.c)
  and its P6 writer were inspected from the locked source. Image-copy or
  wlr-screencopy readback is different from Sunshine's wlr-export-dmabuf path.
- The factory systemd 255 `systemd.exec` and `systemd-run` manuals describe the
  private mounts, explicit device bindings, and inherited log file descriptors.

This diagnostic cannot establish Sunshine capture, client pairing, audio/input,
end-to-end latency, or sustained frame rate. Those remain separate work.

## First hardware attempt

The operator subsequently ran the test from commit `0938cfc`. Snapshot
`20260906T135057Z-b9a45dfe19c3` reported a passing protected-host postflight
followed by a failed transient GPU test. The system journal records service
startup at 13:50:57 UTC and exit code 1 at 13:50:58 UTC, not a runtime timeout.
The transient unit is no longer loaded. Its current `systemctl show` defaults
are not the historical exit result; the journal preserves that failure.

The error itself remains in the root-private log and is not readable without
sudo. A separate `inspect SNAPSHOT_NAME` branch now produces a redacted error
summary without retrying the test, changing permissions, or modifying host
state. No cause or successful capture is claimed before that inspection.

The first redacted inspection showed that seatd started and Hyprland exited
with `-6` (SIGABRT) during startup, before the log identified an NVIDIA renderer.
The inspector initially selected only Python/wrapper errors, omitting the
compositor's native diagnostics. It now also recognizes the
[pinned Hyprutils logger's severity format](https://github.com/hyprwm/hyprutils/blob/5a7b8cf221914ce4714407950e4ffbdddcd8b66f/src/cli/Logger.cpp),
seatd errors, and C++ exception/abort messages, with the same redaction and
read-only behavior. This is a diagnostic correction, not a GPU startup fix;
the hardware test bundle and its isolation settings are unchanged.

## Startup blockers identified

The expanded inspection of the same attempt exposed two independent issues:

- The private `XDG_RUNTIME_DIR` made Hyprland's full event-socket path exceed
  the 107-byte Linux pathname limit. The runtime now uses `/run/sw/user/r`
  inside the existing private namespace. A pre-launch length check and
  regression tests cover the full pinned signature, both socket names,
  and byte length rather than character count. No persistent host path moved.
- Aquamarine rejected NVIDIA `card1` as non-KMS and subsequently aborted with
  no allocator. [Its pinned device check](https://github.com/hyprwm/aquamarine/blob/1a10fe26a9f7d989c359e6a9ea61aa2e44d06c36/src/backend/Session.cpp#L160)
  uses `drmIsKMS`; [the matching NVIDIA driver](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/580.173.02/kernel-open/nvidia-drm/nvidia-drm-drv.c#L1798)
  omits KMS/atomic features when the modeset parameter is false.

Read-only package inspection found `nvidia-drm-options-modeset0` version
`25.07-1` owns `/etc/modprobe.d/zz-nvidia-drm-override.conf`, which contains
`options nvidia-drm modeset=0`. Its package description identifies it as a
system-compatibility override. The driver package's separate configuration
sets `modeset=1`, but there is no DRM-modeset override in the running kernel
command line and the NVIDIA card has no registered connector entries. This
strongly points to disabled KMS; the root-readable **loaded parameter still
needs direct confirmation**. A config file or missing connectors alone is not
that confirmation.

`check-kms` now reads that parameter without opening a GPU device or launching
anything. Normal capture also refuses loaded `modeset=N` before snapshots or
service creation. No driver config, module, package, initramfs, permission,
headless state, or boot setting was changed. The input-device errors are
expected denials from the private device namespace, not authorization to expose
input. The long-socket fix does not resolve disabled KMS, and neither local
tests nor this diagnosis establish successful hardware capture.

The revised bundle and policy build passed. The policy runs 23 capture tests
and 12 inspector tests, plus the pinned Hyprland configuration parser.
`./scripts/dev check` also passed: lint, documentation checks, 77 Python tests
(one optional test skipped), the snapshot-parser regression, and Nix evaluation.
No privileged capture retry or loaded-parameter check was run by the agent;
sudo still requires the operator's password.
