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

## Still required before any live switch

The transaction primitive is not itself the live operator. A later short
operator must retain the exact headless candidate, capture a private snapshot,
install and verify a persistent timed rollback to generation four before any
registration or isolation, survive loss of the SSH/GUI session, and expose
simple status/confirm/rollback commands. It must pass its own disposable
lifecycle before live authorization.

This plan and its test do not authorize rooting, registering, activating,
isolating, stopping GDM, or rebooting `sparkle-01`.
