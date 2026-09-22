# Sunshine startup diagnostic preparation

The [capture-only hardware test passed](2026-09-06-temporary-capture-host.md).
The next test adds the pinned Sunshine package to that temporary session; it
does not enable a remote-desktop service. Its
[operator contract](../../docs/remote-desktop.md#temporary-sunshine-startup-test)
distinguishes dummy-image encoder initialization from real captured frames.

## Build and offline checks

- Sunshine startup bundle:
  `/nix/store/msvfpmyfv4n7pxj9jq34nd2m7g8g5682-dgx-remote-desktop-sunshine-startup-test`.
- Startup policy:
  `/nix/store/in35rlmw9m0v84gkj1p9i508l3mla215-sparkwerx-private-session-policy`.
- Capture-only bundle after the optional test hook:
  `/nix/store/li3vm75fbc1lf9mxmq7ran8lj0wgz2j3-dgx-remote-desktop-session-test`.
  The earlier hardware PASS remains attached to its original `ssdy…` bundle.
- Both policy builds passed 48 tests and all three Hyprland configuration
  parses. The Sunshine variant also ran its actual `--version` config parser
  in the Nix sandbox, verifying the real settings and an unknown-option
  sentinel without initializing a GPU or server. Factory systemd parsing is
  skipped in the Nix sandbox and exercised by the normal repository tests.
- Repository lint, documentation checks, 129 Python tests, systemd snapshot
  regression, and Nix evaluation passed. Two optional Python checks run in
  their separate Nix policy builds instead of the generic test suite.

The build required no new third-party downloads. The initial policy build's
duplicate copy onto a read-only fixture was corrected before the passing run;
it never reached a host operation. No package pin, active profile, KMS artifact,
factory/access service, boot file, device permission, or firewall changed.
Read-only postflight found exact headless generation five, healthy services/GPU,
and no remaining temporary capture unit.

## Hardware status

**Sunshine startup is not yet tested on the GPU.** The normal-user front door
`scripts/test-remote-desktop-sunshine.sh` builds the immutable bundle and asks
sudo for its temporary service. It retains the 150-second hard limit and
no-TCP/UDP/no-input policy. Host state must match after cleanup before PASS.
There is no exact confirmation phrase, permanent installation, or reboot.

Record that result separately. Neither this preparation nor a future startup
PASS establishes Sunshine's changing-frame capture, Moonlight performance,
input/audio, or sustained FPS. The KMS trial remains in its already running
test boot, with recovery material retained.
