# Moonlight trial source-cache fix

The `start 4k60` retry after `0efd44e` failed while building the container
fixture, before the container started. The gate reported no live trial launch.
Both trial services were absent during inspection.

## Cause

The sudo gate imported Python modules from the trial's Nix source directory
without disabling bytecode writes. Root created `__pycache__` there despite the
directory's read-only mode. The later fixture build used `cp source/*`, which
failed when it encountered that directory.

`nix-store --verify-path` confirmed changed contents in these two old trial-only
source outputs:

- `/nix/store/53jj88z16bg0fbgaq49favhlaihigk6z-sparkwerx-moonlight-trial-source`
- `/nix/store/lld1b3kzcpq4l225k4l6dqp5fk90lgvb-sparkwerx-moonlight-trial-source`

They are superseded, not repaired or deleted. Do not rerun their old launchers.
The replacement gate's dependency closure contains neither output.

## Correction

- All trial Python launch paths use [`-B`](https://docs.python.org/3.13/using/cmdline.html#cmdoption-B),
  including the sudo gate, fixture, network test, guardian, cleanup, and graphics
  child. Child interpreters need their own flag.
- Each source tree is assembled independently from declared repository files.
  No copy glob or recursive copy carries runtime caches into another output.
- The complete fixture and network-test packages build before sudo. The actual
  container lifecycle still runs only through the privileged gate.
- A regression runs the real wrapper against writable temporary source files.
  Removing `-B` reproduces cache creation and fails the test. The container
  lifecycle also checks fixture/network source integrity after root execution.

## Verification

All 24 targeted tests passed, including in the Nix policy build with the pinned
firewall parser. `./scripts/dev check` passed: 188 tests, three expected skips,
lint, documentation checks, and flake evaluation. All nine replacement build
steps completed, including the previously failing fixture source and wrapper.
All three fresh source outputs passed `nix-store --verify-path`; the live
wrapper's read-only help invocation left its source intact.

| Artifact | Replacement |
| --- | --- |
| Trial source | `/nix/store/42n7pn5i34wz2iq9j9im0pnsn25kgh0r-sparkwerx-moonlight-trial-source` |
| Trial | `/nix/store/bzk4c0kx84x6jn1pylmwcv6qmfp40fcy-sparkwerx-moonlight-trial` |
| Fixture | `/nix/store/llnqsc0jczim2v16hb0prnl57kcn2s3f-sparkwerx-moonlight-trial-fixture` |
| Policy | `/nix/store/dwfmxw5kpicyv3miw5qxcpjjy7rmhjdc-sparkwerx-moonlight-trial-policy` |
| Pre-launch gate | `/nix/store/s8nxnnm799sxix2lzc029h5z6xwm218x-sparkwerx-moonlight-trial-gate` |
| Container recipe, not yet passed | `/nix/store/ay84v5mfis6wq946a2imlnihcm3fswcd-container-test-dgx-moonlight-trial-lifecycle.drv` |

The original Sunshine, startup, changing-frame, private-input, and headless
root outputs remain exact. No pins, profiles, services, firewall rules, device
permissions, desktop mode, KMS settings, or boot files changed.

The privileged lifecycle still needs sudo and has not passed yet. Retry the
same [trial launcher](../../docs/moonlight-trial.md); it must pass that exact
test before starting the real session.
