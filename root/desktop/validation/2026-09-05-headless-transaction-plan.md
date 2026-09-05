# Generation-four to headless transaction plan — 2026-09-05

## Current state

The thin headless/factory-GNOME controller has passed its ten-subtest,
three-reboot disposable lifecycle. `sparkle-01` remains on exact System Manager
generation four with factory GNOME and Nix-managed Tailscale. No desktop
controller path, generation-five registration, or headless pilot root has been
created on the host.

## Transaction primitive

`scripts/root-desktop-mode-transaction.sh` implements one deliberately narrow
transition:

1. verify exact registered/live generation four, factory GNOME, Nix-managed
   Tailscale, all four earlier direct pilot roots, and a separately retained
   exact headless candidate;
2. register the headless candidate as generation five;
3. activate its persistence-only declaration;
4. explicitly isolate `dgx-headless.target`; and
5. verify exact generation five, inactive graphics/GDM, active Tailscale, and
   the known System Manager state surface.

Its rollback activates exact generation four, restores factory
`graphical.target`, reselects generation four, synchronizes the upstream GC
root, removes only the exact generation-five profile link, and retains every
direct pilot root. Unknown profile entries, roots, candidate paths, or injected
failures stop closed.

## Disposable proof gate

`root/desktop/headless-transaction-test.nix` exercises twelve cases in a
disposable Ubuntu container, including foreign-path refusal, failures after
registration/activation/isolation, successful headless operation, duplicate
apply refusal, foreign-root preservation, and idempotent exact rollback. It
also requires the fake Nix-managed Tailscale process and protected-file hashes
to remain unchanged.

Run the root-assisted host-boundary wrapper only from a clean commit:

```bash
sudo ./scripts/test-desktop-headless-transaction.sh
```

The wrapper checks exact live generation four before and after the container
build and compares protected service identity. All mutation occurs in the
container.

The exact 12-subtest derivation passed from commit `71bd7c4` with clean
live-host postflight. See the
[result](2026-09-05-headless-transaction-container-test.md).

## Guarded live-operator design

`scripts/dgx-desktop` now wraps that primitive with the short interface
`plan|headless|status|confirm|rollback|cleanup-rolled-back`. The `headless`
action retains the exact candidate and immutable rollback bundle, captures a
private host snapshot, installs a persistent ten-minute generation-four/
factory-GNOME timer, and starts a detached worker. Both the timer and worker
ignore target isolation, so closing a GUI terminal or losing an SSH client
cannot cancel recovery. Confirmation has no fragile typed phrase: invoking
`confirm` after exact postflight is the decision.

`root/desktop/switch-lifecycle-test.nix` exercises same-boot automatic
rollback, confirmed retention, explicit factory rollback, a headless reboot
with automatic factory recovery, Tailscale continuity, and complete candidate-
root retention in a disposable Ubuntu container. The host-boundary wrapper is:

```bash
sudo ./scripts/test-desktop-switch-lifecycle.sh
```

That lifecycle is the remaining proof gate. Until its exact result is recorded
as current and passed, do not run `./scripts/dgx-desktop headless`.

This plan and its test do not authorize rooting, registering, activating,
isolating, stopping GDM, or rebooting `sparkle-01`.
