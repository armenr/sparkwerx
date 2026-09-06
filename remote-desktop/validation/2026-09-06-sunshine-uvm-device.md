# Sunshine CUDA initialization and the missing UVM device

The CUDA-enabled package reached the correct encoder implementation, but the
temporary test hid `/dev/nvidia-uvm`. Denying that device independently reproduced
the same `CUDA_ERROR_UNKNOWN`. The harness now exposes that existing device
only for the Sunshine test; its full GPU rerun is still pending.

## Reported failure

The user ran commit `f20b12f` against Sunshine output
`/nix/store/3j2b6777c4i5kvikzw4ghfjz6qmfhafj-sunshine-2026.516.143833`.
The private snapshot is `20260906T201017Z-77f5acae959d` under the pilot's
`inventory/sparkle-01/raw/remote-desktop-session/` directory. The reported host
postflight passed. Its redacted inspector showed:

```text
Trying encoder [nvenc]
Screencasting with Wayland's protocol
[wlgrab] Resolution: 3840x2160
Couldn't initialize cuda: CUDA_ERROR_UNKNOWN:unknown error
```

In the [pinned Sunshine source](https://github.com/LizardByte/Sunshine/blob/v2026.516.143833/src/platform/linux/cuda.cpp),
that last message comes directly from `cuInit(0)`, before encoder-device setup.
It is distinct from the previous CUDA-disabled build failure.

## Reproduction on the pilot

The factory `nvidia_uvm` module was already loaded. Its device was an existing
root-owned character node, major 498/minor 0, with mode 0666. No module load or
device creation was necessary. NVIDIA documents UVM as a CUDA driver component
for CPU/GPU memory sharing in its [driver component list](https://download.nvidia.com/XFree86/Linux-x86_64/580.173.02/README/installedcomponents.html).

As `n0b0dy`, using the diagnostic's exact Nix Python 3.13.15 and factory
`libcuda.so.580.173.02`, a small `ctypes` call to `cuInit(0)` produced:

| Check | Result |
| --- | --- |
| Normal access, traced only at the UVM nodes | Two successful `/dev/nvidia-uvm` opens; `CUDA_SUCCESS` (0) |
| Same call, with `strace` injecting `ENOENT` only for opens of `/dev/nvidia-uvm` | `CUDA_ERROR_UNKNOWN` (999) |

Both calls ran with `setpriv --no-new-privs`, without sudo, so a driver helper
could not gain privileges. The injection affected only the child process;
the actual device remained present with its original ownership and mode.
These checks initialized the GPU briefly but did not render or encode video.
They establish the missing-device problem, not a completed Sunshine stream.

## Harness correction

- Sunshine gets the original five graphics nodes plus `/dev/nvidia-uvm`, through
  both the private bind and exact `DeviceAllow` entry.
- Capture-only retains its original five nodes and rejects UVM exposure.
- Both variants keep `/dev/nvidia-uvm-tools`, input devices, host IPC, and TCP/UDP
  inaccessible. The 150-second deadline and all other unit restrictions remain.
- Preflight and in-namespace checks require a root-owned, non-symlink character
  node whose major/minor matches the loaded `nvidia-uvm` driver. Missing nodes
  fail the test; the harness never creates/chmods nodes or loads modules.
- Host before/after snapshots now include both UVM nodes' ownership, modes,
  device numbers, and extended attributes.

No package, lock, driver, root generation, persistent service, or boot setting
changed. The [CUDA package adapter](../../packages/sunshine/README.md) remains
necessary and unchanged.

## Validation and next run

The capture unit suite passed 29 tests, including factory systemd syntax checks
for both variants without starting them. Both Nix session policies passed their
59-test suites and three Hyprland configuration parses; the sandbox lacks the
factory systemd parser, and capture-only also skips Sunshine's parser test.
`./scripts/dev check` passed its 140-test suite (two optional checks skipped),
lint, documentation, and Nix evaluation.

Built artifacts:

- Sunshine test: `/nix/store/nfx268pc52f9b97b4z8k0yv9ngbd9rb6-dgx-remote-desktop-sunshine-startup-test`
- Sunshine session policy: `/nix/store/by852qyi7zr28q4i310hz4zccvkihyqd-sparkwerx-private-session-policy`
- Capture-only test: `/nix/store/iy6lcyyh0h26m601ipascq8abip4fvkn-dgx-remote-desktop-session-test`
- Capture-only policy: `/nix/store/q3cx0mvlnv0xj5arngc161aag6rfp103-sparkwerx-private-session-policy`

The pilot's selected generation remained
`/nix/store/djp7ap9gc7kq6c5hhbqzzslvmg4vq3m1-system-manager`, with the expected
headless service states, no pending protected-unit reload, and GB10 driver
580.173.02. The new UVM preflight accepted the actual host device read-only.

The full temporary session still needs the operator's sudo password:

```bash
./scripts/test-remote-desktop-sunshine.sh
```

Do not turn the diagnosed `cuInit` failure into a claim that later CUDA/GL
interop, encoder initialization, or changing-frame capture has passed.
