# Private Wayland input preparation

The separate Sunshine input adapter and diagnostic build on ARM64. No hardware
input run or Moonlight connection has occurred in this preparation step.

## Checks passed

- A real private Unix-socket Wayland fixture receives keys, Shift modifiers,
  releases, relative/absolute motion, buttons, and both scroll axes. Duplicate
  key events are suppressed and coordinates are clamped.
- A wrong output, missing virtual-pointer protocol, or second seat is rejected.
- Sunshine compiles with the new input backend and the existing CUDA adapter.
  The original capture/encoder source checksums still match.
- The package's version-only startup and driver-library wrapper checks pass
  with absent, empty, and existing library paths. This caught an upstream
  assumption that the gamepad descriptor list is nonempty during static
  configuration initialization. The adapter now returns one explicitly
  disabled descriptor; controller allocation always fails.
- Seven orchestration tests require the full input receipt, stop failed
  clients, and preserve the existing no-IP/no-kernel-input service isolation.
- `./scripts/dev check` passes: lint/formatting, documentation, 164 tests with
  three expected skips, and Nix flake evaluation.
- The package installs no service or udev rule. Nothing was activated or added
  to a profile, and host device permissions were not changed.

| Artifact | Store output |
| --- | --- |
| Trial Sunshine | `/nix/store/m7x0afkc8j4znk35wlkrg8gg85d8rwn6-sparkwerx-sunshine-wayland-input-2026.516.143833` |
| Protocol fixture/exerciser | `/nix/store/gsz34k21dsdsy8h4bls1080qk2xadln8-sparkwerx-wayland-input-test` |
| Hardware-test wrapper | `/nix/store/f63h4mqn8dxfii4hvgrzpgzp6vps1mr2-dgx-remote-desktop-input-test` |
| Input/package policy | `/nix/store/xam1xw9cvn501q7px02vpm612qxl5ksa-sparkwerx-private-input-policy` |

The original Sunshine output remains
`/nix/store/3j2b6777c4i5kvikzw4ghfjz6qmfhafj-sunshine-2026.516.143833`.
The [passed offline frame test](2026-09-07-sunshine-frames-host.md) also retains
its exact wrapper and capture executable. Its supervisor is reused unchanged
by the new diagnostic, through a separate source bundle and tools manifest.

## Hardware check still required

Run as the normal user on the Spark:

```bash
./scripts/test-remote-desktop-input.sh
```

Sudo is requested only for the existing 150-second private Hyprland supervisor.
It checks adapter startup, repeats color/NVENC checks, and sends synthetic
keyboard/mouse events to a dedicated fullscreen receiver. Success requires
lowercase and shifted uppercase input, releases, motion, clicks, and both
scroll axes. Diagnostics retain counts, not typed text.

TCP/UDP and kernel input devices stay denied. This is not a client test, and
does not start the approved 30-minute Moonlight trial. That launcher still
needs its own network guard, private administration, timeout, and cleanup
tests. See the [operator contract](../../docs/remote-desktop.md#private-keyboard-and-mouse-check).
