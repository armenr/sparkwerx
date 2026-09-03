# User/package dependency refresh

Date: 2026-09-03 UTC

Host: `sparkle-01`

Result: passed; no activation

## Pins advanced

- stable user/fleet Nixpkgs: `a9e6d84f9c2f...` to `a3116115851d...`;
- fast apps Nixpkgs: `a831408e6378...` to `9387b3fcc0c2...`;
- Home Manager remained `65258d5c65a2...`, already the current
  `release-26.05` head; and
- Tailscale remained 1.102.3, already the current official stable ARM64
  release.

The post-update online audit confirmed the stable, apps, Home Manager, System
Manager, Nix 2.35.2, Tailscale, Devbox, ncdu, lazydocker, Ghostty, Chromium,
and Hyprland candidates are current against their selected official channels.
Zed 1.18.0, LM Studio 0.4.23-1, and Codex CLI 0.153.0 remain explicit upstream
application updates requiring their narrow package/ownership work; they are
not hidden by the fact that the Nixpkgs branches themselves are current.
Codex was subsequently packaged and build-validated later the same day; see
[the Codex package evidence](2026-09-03-codex-cli-package.md). Exact official
ARM64 packages for Zed 1.18.0 and LM Studio 0.4.23-1 were subsequently pinned,
built, and closure-reviewed as well. Their graphical validation/profile
activation remains open; see the [Zed](2026-09-03-zed-package.md) and
[LM Studio](2026-09-03-lmstudio-package.md) records. The locked current
Chromium 152.0.7977.75 package was subsequently realized and closure-reviewed;
its required non-NixOS root sandbox integration remains open. See the
[Chromium record](2026-09-03-chromium-package.md).

## Safety and build result

Before and after the lock mutation, `scripts/update-dependencies.sh` evaluated
the complete frozen root fingerprint: all three System Manager candidates,
the recovery bundle, root policy, and six disposable test derivations. The two
fingerprints were exactly equal.

The full flake evaluation then passed. Every Home Manager profile plus the
Devbox, Tailscale, Hyprland, portal, root canary, and policy outputs built with
`--no-link`. Exact realized Home Manager generation closure sizes are:

- headless/base: 572.3 MiB;
- GNOME + Ghostty: 1.4 GiB;
- Hyprland without portal: 2.0 GiB; and
- Hyprland with portal: 3.3 GiB.

No Home Manager generation, application, root profile, systemd unit, service,
desktop mode, or Tailscale binary was activated or replaced.

Later the same day, the separately guarded minimal headless Home transaction
activated only the reviewed base plus Armen's Codex overlay, passed real
rollback, and retained a fresh generation. That later result does not change
this refresh's no-activation boundary; see the
[Home host record](2026-09-03-home-headless-host.md).
