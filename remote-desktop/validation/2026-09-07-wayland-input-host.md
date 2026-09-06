# Private keyboard and mouse receipt on the GB10

Armen ran `./scripts/test-remote-desktop-input.sh` successfully using commit
`4867b29`. The private snapshot is `20260906T222414Z-57ebc2f10f6b`.

The separate Sunshine adapter initialized its session-local Wayland keyboard
and pointer. A dedicated Hyprland client received the synthetic key presses,
releases, lowercase/Shift-uppercase input, mouse movement, clicks, and both
scroll axes required by the verifier. NVENC initialized H.264, HEVC, and AV1,
and Grim verified red/green pixels at the requested 4k120 preset.

The supervisor stopped its clients, compositor, and broker. Host postflight
passed: root profile, protected processes, Tailscale access, configuration,
and device permissions were unchanged. The run kept the 150-second deadline,
denied TCP/UDP and kernel input devices, and changed no desktop or boot mode.

The [preparation record](2026-09-07-wayland-input-preparation.md) identifies the
exact package, protocol fixture, wrapper, and policy outputs; those outputs
were used unchanged. The generic shared supervisor's `NOT_STREAMING` line
does not describe this extra synthetic-input result. Its final
`PASS|private_input_test` does. Neither line establishes Moonlight transport,
client input dispatch, audio, latency, or sustained frame rate.

Next is the separately authorized 30-minute Tailscale-only client trial, with
private administration and automatic shutdown. The passed offline diagnostics
remain separate and unchanged.
