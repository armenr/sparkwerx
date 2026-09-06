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
