# Post-Tailscale integration regression — 2026-09-05

> Historical pre-desktop evidence. The later complete generation-five/headless
> retained-state regression supersedes this as current integration authority;
> see
> [the confirmed headless integration record](../root/desktop/validation/2026-09-05-confirmed-headless-integration.md).

## Result

**PASS.** After the real apt-to-Nix Tailscale handoff and guarded reboot were
confirmed, the complete operator-facing integration regression passed on
`sparkle-01` from commit `77518de3e5c352bb8447ea684e71205b109c7ff0`:

```console
./scripts/test-post-tailscale-integration.sh
```

The final result was:

```text
PASS|dgx_setup_plan_test|declaration, bootstrap adoption, Nix-managed Tailscale, remaining role gates, privacy, and zero-mutation checks passed
PASS|tailscale_unit_lifecycle|container handoff/reboot/rollback passed; live host stayed exact
PASS|dgx_setup_apply_test|Nix, Home, and Nix-managed Tailscale converged as no-ops; desktop, root, services, and mutable state stayed exact
PASS|post_tailscale_integration|plan, Nix bootstrap lifecycle, Tailscale lifecycle, and live staged-apply no-op all passed
```

The clean-host Nix bootstrap lifecycle also returned success inside the
wrapper. It is intentionally quiet on success. The two root-requiring tests
ran only in disposable Ubuntu containers; they did not migrate, reboot, or
otherwise mutate the live host.

## Exact disposable evidence

The successful outputs remain the current derivations after the follow-up
portability fix:

| Test | Derivation | Output |
| --- | --- | --- |
| Clean-host Nix bootstrap/rollback/retry/adoption | `/nix/store/zdc2aws529yvapwrwamfj9d8jn7ly1ys-container-test-dgx-nix-bootstrap-lifecycle.drv` | `/nix/store/62wj907ivs3pf9kaz1051diyn90732j3-container-test-dgx-nix-bootstrap-lifecycle` |
| Apt-to-Nix Tailscale handoff/two-reboot/rollback | `/nix/store/z3ygmg4cm0hhc3bvng7kgcwy09a2p0ba-container-test-dgx-tailscale-unit-lifecycle.drv` | `/nix/store/ivwvkzzkipk1bv9ai9pm9zqxh8ix93zw-container-test-dgx-tailscale-unit-lifecycle` |

The Nix bootstrap output is 7,104 bytes with NAR hash
`sha256-HDLkrmJCtL33zpBGs9OljB8glpaj3YKYoEt+iHmkZxE=`. The Tailscale
lifecycle output is 12,232 bytes with NAR hash
`sha256-vmTp1jrLNnNibQhpInpaXfbPAA+5UiCp5Z4k7lbo2lw=`.

The warning that `auto-allocate-uids` was ignored is the known direct-store
client warning. The isolated root test enables the required experimental
features itself and passed; the warning is not a skipped lifecycle step.

## Portability issue exposed and closed

The passing live apply printed:

```text
scripts/dgx-home: line 165: rg: command not found
```

The check still reached PASS, but this revealed that the operator depended on
`ripgrep`, which is not part of the declared minimal host profile. Commit
`d81441d180f5ff66426ba6760b45908397230f7e` replaced that one read-only
content check with factory `grep`.

The corrected script passed ShellCheck and the Home/profile checks. It was then
run with a deliberately restricted factory/Nix PATH containing no `rg`:

```text
INFO|live_candidate|/nix/store/naw1cln02ark00v6wxss5flijlh3nr57-home-manager-generation
INFO|repository_candidate|/nix/store/naw1cln02ark00v6wxss5flijlh3nr57-home-manager-generation
PASS|preflight|live headless Home generation already matches the repository; no update is needed
PASS|update|already current; no snapshot, profile generation, timer, or host state changed
```

The full evaluation-only `scripts/check.sh` and the read-only plan regression
also passed after that fix.

## Retained live boundary

- System Manager generation four remains selected, live, and boot-linked at
  `/nix/store/vjw778sf95r42a1zbivlk8z4p45y7qhx-system-manager`.
- Nix owns the active `/etc/systemd/system/tailscaled.service`; Tailscale
  1.102.3 remains online with SSH enabled and its identity unchanged.
- The Home profile remains
  `/nix/store/naw1cln02ark00v6wxss5flijlh3nr57-home-manager-generation`.
- The migration guard and rollback timer remain absent. The apt package and
  repository remain only as deliberately retained, inactive fallback material.
- Factory GNOME/GDM, the root desktop controller, graphical overlays, and all
  workload roles remain untouched and separately gated.

This closes the post-Tailscale integration gate for the currently implemented
Nix, headless Home, and Tailscale layers. `APPLY_STATUS=PARTIAL` remains the
honest success state until the independent root desktop controller is built and
approved.
