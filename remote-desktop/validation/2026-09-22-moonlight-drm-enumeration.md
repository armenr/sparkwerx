# Moonlight trial: GPU device renumbering after reboot

## Cause

After the successful persistent-KMS reboot, `start 4k120` stopped during
preflight because `/dev/dri/card1` did not exist. No disposable test, real
graphics worker, or streaming listener started from that attempt.

Read-only host inspection found the same NVIDIA GB10 at `/dev/dri/card0`,
with `/dev/dri/renderD128` belonging to the same PCI device. The driver is
`nvidia`, vendor/device IDs are `10de:2e12`, and the device numbers are
`226:0` and `226:128`. Both nodes are root-owned. The trial had inherited
fixed paths from the original offline capture diagnostic.

DRM enumeration is not stable GPU identity. Hyprland's
[GPU-selection documentation](https://wiki.hypr.land/configuring/extra/multi-gpu/)
also warns against using a fixed card number as an identity and notes that
colon-containing PCI by-path names conflict with `AQ_DRM_DEVICES` separators.

## Correction

The trial-only [selector](../trial-devices.py) requires one NVIDIA GB10 PCI
card and its unique render node, with matching kernel device numbers and
root-owned character devices. It saves the selection with trial evidence and
revalidates it in the guardian, root worker, and unprivileged graphics child.

Device mounts, device-cgroup rules, child-only groups, host metadata checks,
and Hyprland's environment use that selected pair. The private DRM directory
must expose only those two nodes. Missing/ambiguous devices, another GPU's
render node, changed identity, aliases, or wrong device metadata stop launch.
No host aliases, udev rules, permissions, groups, or driver settings are changed.

The trial retains the offline diagnostic's host/KMS/access preflight checks
in its own adapter. The original capture, startup, and changing-frame source
and Nix outputs remain unchanged; this is not a rewrite of their passed results.

## Verification

CPU fixtures cover old/new card numbers and render renumbering, wrong GPU
identity, ambiguous/mismatched nodes, owner/type/device-number rejection,
saved-context changes, exact private-device exposure, worker bindings,
compositor selection, child validation, and retained host preflight gates.

Read-only discovery through the built Nix source on the actual host selected
`card0` and `renderD128`; `nix-store --verify-path` confirmed source integrity
after import. All 52 trial policy tests passed in Nix. `./scripts/dev check`
passed 267 tests with six expected skips, lint, documentation checks, and
flake evaluation. The original Sunshine, Wayland-input, capture, startup,
and changing-frame output paths matched their pre-edit values exactly.

Built trial: `/nix/store/m0p2fxb4j77a5144qw9ay9pm6qcbq9j0-sparkwerx-moonlight-trial`.
Built gate: `/nix/store/bsf4b0kx5wajyxjv7x8lk1pspfjrxdm4-sparkwerx-moonlight-trial-gate`.
Passed policy: `/nix/store/hgb82i4h46bv2pnkaydslamzblqkn8yi-sparkwerx-moonlight-trial-policy`.
Unrun container recipe:
`/nix/store/1y5ml1wy30hd1wmxgpyhm7b131qbnhj8-container-test-dgx-moonlight-trial-lifecycle.drv`.

The corrected privileged lifecycle and live stream still require the next gated launch;
they have not been reported as passed here. No host service, firewall, boot
setting, driver, device permission, or desktop mode was changed by this fix.

Run the same front door:

```bash
./scripts/dgx-moonlight-trial start 4k120
```

It prints the chosen device paths, runs its exact disposable lifecycle, and
starts the temporary session only if that test and host postflight pass.
