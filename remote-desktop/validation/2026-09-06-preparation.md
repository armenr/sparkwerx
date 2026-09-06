# Sunshine preparation: package and network tests

The operator reported a passing `./scripts/test-remote-desktop-preparation.sh`
run on sparkle-01 from commit `0b28ff28f9c990cb1d18188668ba374fbb1c788a`.

```text
PASS|remote_desktop_network|32 IPv4/IPv6 TCP/UDP probes; admin forwarding and unrelated table preserved
PASS|remote_desktop_preparation|selection, package build, network rules, and host non-mutation verified; capture/streaming still untested
```

The test uses fake Tailscale/LAN interfaces and echo listeners in disposable
network namespaces. It verifies streaming-port reachability on `tailscale0`,
rejection on the other interface, rejection of direct remote admin access,
and the local connection path needed by an SSH forward. An earlier accepting
firewall chain does not bypass the guard, and its unrelated table is preserved.
This does not test a real Sunshine listener, SSH forwarding protocol, Moonlight
pairing, tailnet grants, or video/audio/input streaming.

The local Python run reports ten tests with one skip. That skip is the Nix/Python
plan comparison, which runs inside the Nix policy build instead. Its build log
was independently read and reports ten passing tests without skips.

## Exact artifacts

| Artifact | Value |
| --- | --- |
| Sunshine | `/nix/store/l6phapr6sk3y3q3bdv0m19r8dm78s5yb-sunshine-2026.516.143833` |
| Policy output | `/nix/store/9v4089b6g81s1i7079anh6wa50badijb-sparkwerx-remote-desktop-policy` |
| Network-test bundle | `/nix/store/f211bpjfa4kpk2hngs2gy3vi01va1m3h-dgx-remote-desktop-network-test` |
| Network-test derivation | `/nix/store/ahabcnz3wkkbp9xx74l1z3q3g0zzbx1k-dgx-remote-desktop-network-test.drv` |
| Wrapper SHA-256 | `2b4d4056f11f2315cebd00e3d79d95397d0d38db0f1c3d71b3811130f191e0e0` |
| Firewall source SHA-256 | `3cd48c0de2a913cdaed94830ea1079fd752322d00b6cc0d32667de0e307aab5a` |
| Packet-test source SHA-256 | `fb4a0bb5bd37dc47ad1d8f589a05bc604c4647df53096184aff38335b6f48ac6` |

## Read-only graphics follow-up

The factory Python loader successfully loaded `libnvidia-encode.so.1` and
`NvEncodeAPIGetMaxSupportedVersion` returned status 0, API 13.0. That query only
reports driver API compatibility; it opened no encoding session. It is not
proof of NVENC encoding or the Nix-to-factory graphics-library bridge. See the
[API contract](https://raw.githubusercontent.com/FFmpeg/nv-codec-headers/n13.0.19.0/include/ffnvcodec/nvEncodeAPI.h)
and [NVIDIA's encoding flow](https://docs.nvidia.com/video-technologies/video-codec-sdk/13.0/nvenc-video-encoder-api-prog-guide/index.html).

The current SSH user cannot read/write the NVIDIA DRM card or render node, and
cannot write `/dev/uinput`. Remote graphics/input access needs a scoped design;
no permissions or group memberships were changed. A connected `Unknown-1`
connector belongs to `simple-framebuffer`, so it does not establish a usable
NVIDIA capture display or the user's future monitor arrangement.

Independent observation still finds generation five selected, headless active,
GDM/Dashboard GUI inactive, Tailscale active, and no pending reload on those
units. The next design input is the client device/display and whether the Spark
must stream without a monitor. No desktop, service, firewall, or reboot change
was performed while recording this result.
