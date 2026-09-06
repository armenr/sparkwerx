# Chromium package evidence

Date: 2026-09-03 UTC

Host: `sparkle-01`

Result: current ARM64 package and closure policy passed; sandbox integration,
profile activation, and graphical validation remain open

## Source and ownership

Chromium is Armen's selected graphical browser; Google Chrome remains
explicitly unselected. The package comes from the independently locked
`nixpkgs-apps` lane, whose exact source and build inputs are fixed by
`flake.lock`.

- version: `152.0.7977.75`;
- architecture: `aarch64-linux`;
- apps revision: `9387b3fcc0c23c86661636da63faabad4235a0a6`;
- package derivation:
  `/nix/store/0qmvan2azg77faaj11zqlrryhjygsby4-chromium-152.0.7977.75.drv`;
- package output:
  `/nix/store/pq08ww45376r95p7kfpgrgzvqfy21k5d-chromium-152.0.7977.75`;
- sandbox output:
  `/nix/store/p3ilpzs2wwjgf5b1gvps5pp9saa9dwm6-chromium-152.0.7977.75-sandbox`;
- official release comparison:
  `https://chromiumdash.appspot.com/releases?platform=Linux`; and
- package update path: the guarded user/apps lock refresh in
  [`scripts/update-dependencies.sh`](../scripts/update-dependencies.sh), followed
  by the online audit and package/policy rebuild.

The 2026-09-03 online audit found the package equal to the newest official Linux
stable release. A branch update is only an available candidate until that
comparison and these runtime gates pass again.

## Closure and declared side effects

The realized package closure is 340 paths / 1,842,653,168 bytes (about 1.7 GiB
NAR). The package wrapper output is 4,304 bytes; the unwrapped browser output is
691,685,504 bytes with a 943,087,864-byte closure. At the time of realization,
the binary cache plan added 195.2 MiB compressed / 672.5 MiB unpacked because
many dependencies were already present.

The direct output contains the browser wrapper plus links to icons, its manpage,
and one desktop entry. It declares no system or user service, socket, timer,
autostart, or listening port. The desktop entry advertises common web/PDF/image
types plus HTTP, HTTPS, and `chromium:` URL handlers; no Home Manager MIME
default is declared.

Browser profiles, cookies, history, extensions, 1Password enrollment, sync
state, credentials, downloads, caches, and crash data remain mutable and
outside the Nix store. The existing Firefox profile and its 1Password extension
were not inspected or changed. Chromium's selected 1Password extension remains
a separate artifact/update-policy gate.

## Required sandbox integration

The package wrapper prefers
`/run/wrappers/bin/__chromium-suid-sandbox` and otherwise points Chromium at the
immutable sandbox helper in the Nix store. Store files cannot carry the
required setuid bit; the exact helper is root-owned mode `0555`. A headless,
isolated-home launch therefore failed closed with Chromium's expected demand
for a root-owned mode-`4755` helper. Retrying with the setuid sandbox disabled
also failed closed because the factory Ubuntu AppArmor policy blocks the
browser's unprivileged user namespace.

Chromium's own
[Ubuntu AppArmor guidance](https://chromium.googlesource.com/chromium/src/+/main/docs/security/apparmor-userns-restrictions.md)
warns never to browse the open web with `--no-sandbox`. That fallback is not
accepted here. Globally disabling
`kernel.apparmor_restrict_unprivileged_userns` is also rejected.

The preferred next design is a narrow graphical root role that installs this
exact version-matched helper at Chromium's expected `/run/wrappers/bin` path as
root-owned mode `4755`. This matches the locked Nixpkgs
[`security.chromiumSuidSandbox` module](https://github.com/NixOS/nixpkgs/blob/9387b3fcc0c23c86661636da63faabad4235a0a6/nixos/modules/security/chromium-suid-sandbox.nix).
It is still a setuid/root-security change, so it requires a dedicated System
Manager generation, disposable test, collision snapshot, timed rollback, and
separate live authorization. An exact-path AppArmor user-namespace profile is a
possible alternative, but it likewise belongs in that reviewed root role and
must not use a broad path glob.

## Validation and remaining gate

The exact package and `chromium-policy` derivations passed. The policy verifies
the current version, free-license evaluation, browser and helper outputs,
expected non-setuid store mode, wrapper's preferred runtime path, desktop entry,
and absence of service/autostart surfaces. The profile policy also proves that
Chromium, Zed, and LM Studio are absent from every current Home profile.

Chromium remains selected and built but not installed. After the sandbox root
role is independently proven, the remaining user-level gate is a disposable
factory-GNOME profile test covering NVIDIA rendering, Wayland/X11 behavior,
portals, MIME prompts, profile paths, and rollback. The 1Password Chromium
extension must be pinned and tested separately before the full overlay is
activated.
