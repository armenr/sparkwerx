# First Moonlight client connection

The temporary Tailscale-only trial connected from Armen's 16-inch Apple M1 Max
MacBook Pro using its built-in display. Pairing, HEVC video, keyboard, mouse,
clicks, and scrolling worked. This is a private test canvas, not the installed
user desktop; audio remains intentionally off.

## Measured result

The performance overlay in the user-supplied screenshot showed:

| Measurement | Value |
| --- | --- |
| Stream | 3840×2160, HEVC |
| Incoming / decoded / rendered FPS | 32.44 / 32.44 / 32.44 |
| Host processing, min / max / average | 33.9 / 62.0 / 46.3 ms |
| Network frame drops | 0.00% |
| Jitter frame drops | 0.00% |
| Network latency / variance | 32 / 31 ms |
| Average decode time | 6.66 ms |
| Average rendering time, including V-sync | 1.91 ms |

The canvas also showed keyboard, click, and scroll counters advancing. The
requested server/client preset was 4k120; the observed stream was about 32 FPS.
No sustained 120 FPS or end-to-end latency result is established by this image.
Zero drops do not eliminate the visible network-latency variation.

Host frame production/capture is the first investigation target, not a proven
NVENC bottleneck. The canvas follows Wayland frame callbacks and has no explicit
30 FPS cap. Its full-frame SHM damage path remains unchanged for timing tests.
Sunshine's [host-processing field](https://github.com/LizardByte/Sunshine/blob/v2026.516.143833/src/stream.cpp)
includes the path from capture timestamp to packet preparation, not just encoding.
[Sunshine follows content-update cadence](https://github.com/moonlight-stream/moonlight-docs/wiki/Frequently-Asked-Questions#why-is-my-frame-rate-low-when-streaming-static-content-from-sunshine)
up to the client's requested FPS.

## Exact tested artifacts

- Repository commit: `23d260e` on `feat/temporary-hyprland-capture-test`.
- Trial: `/nix/store/bzk4c0kx84x6jn1pylmwcv6qmfp40fcy-sparkwerx-moonlight-trial`.
- Passed lifecycle derivation:
  `/nix/store/ay84v5mfis6wq946a2imlnihcm3fswcd-container-test-dgx-moonlight-trial-lifecycle.drv`.
- Passed lifecycle output:
  `/nix/store/lwibzfml3qzdcgzczpqvsh35x0cxdsxr-container-test-dgx-moonlight-trial-lifecycle`.

The operator reported its disposable lifecycle PASS and launched the real
trial only afterward. The passed output was independently found in the store.
The later 4k120 trial services started at 04:58:35 UTC. At 05:30:09 UTC both
temporary units were inactive/not loaded, consistent with their existing
30-minute deadline. Generation five remained selected. Full private cleanup
evidence still requires the root-readable `inspect` result; unit absence alone
does not verify firewall cleanup or every protected-host field.

## Client connection lesson

Native macOS `ssh` could not resolve the short name while `tailscale ssh`
worked. The successful tunnel uses Tailscale peer resolution and places
OpenSSH flags after the destination. Use the corrected
[trial guide](../../docs/moonlight-trial.md#open-sunshine-administration-through-ssh).
Moonlight was manually given the Spark's Tailscale address. No DNS, host-key,
tailnet policy, or firewall relaxation was needed.

## Follow-up timing tools

The canvas now measures submissions/callbacks and client-side paint duration
over five-second windows, with a submission-rate label on screen. The inspector
extracts numeric canvas and existing Sunshine timing records. It reports when
log prefixes or middle samples were omitted and never exposes raw client details.
No capture engine, encoder option, networking, device permission, or deadline
was changed to obtain these measurements.

Validation:

- `./scripts/dev check`: 195 tests, three expected skips; lint, documentation,
  shell property checks, and Nix evaluation passed.
- 31 trial policy tests passed, including malformed/private data rejection and
  retaining early canvas records ahead of a large Sunshine log tail.
- The built C canvas passed synthetic 30/60/120 submission-clock self-tests
  without opening a display.
- Trial, policy, network/fixture tools, and gate built with `--no-link`.
- Ordinary Sunshine and all three passed offline startup/frame/input diagnostic
  output paths remained exact.

Candidate: `/nix/store/593n1x71m9iaxhbbrhmm4qkqxwcdaqad-sparkwerx-moonlight-trial`.
Policy: `/nix/store/3i42sih8ryvwrv3s8dn9rfs0z03hy81a-sparkwerx-moonlight-trial-policy`.
The revised lifecycle derivation is
`/nix/store/0baw4dz98jsfvl2gpp6w90vz7dk4c5l8-container-test-dgx-moonlight-trial-lifecycle.drv`;
it has not been run with root for this revision. The launcher still requires
its PASS before a new live trial. The instrumentation is not part of the
screenshot's measured run. Build/self-test results do not replace the next
client measurement. The next read-only step is `./scripts/dgx-moonlight-trial inspect`
on the finished trial, which needs the operator's local sudo prompt.

No private screenshot, address, pairing credential, or raw log is copied here.
