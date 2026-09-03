# First headless Home activation preflight

Date: 2026-09-03 UTC

Host: `sparkle-01`

Result: exact profile, collision review, non-mutating dry run, and disposable
rollback test passed; live activation remains open

## Exact generation

The first user-layer generation is intentionally smaller than the running
factory GNOME session. `headless` here describes Home profile composition; it
does not stop GDM or change the host target.

- activation package:
  `/nix/store/naw1cln02ark00v6wxss5flijlh3nr57-home-manager-generation`;
- profile packages: `ncdu` 2.9.2, `lazydocker` 0.25.2, Devbox 0.18.0, and
  Armen's Codex CLI 0.153.0;
- activation closure: 52 paths / 696.8 MiB;
- installed `home-manager-path` closure: 643.2 MiB; and
- Home Manager CLI/manpages: absent by policy.

The fleet base remains exactly the first three packages. Codex is an explicit
Armen all-modes overlay, not part of the fleet base. Chromium, Ghostty,
Hyprland, Zed, LM Studio, portals, XDG ownership, and every personal graphical
application remain absent.

## Side effects and collisions

Disabling `systemd.user.enable` in the headless profile suppresses Home
Manager's otherwise generic `tray.target`, its `environment.d` file, and the
entire user-systemd reload phase. The exact home-file surface is now only:

- `.local/bin/codex`;
- `.cache/.keep`; and
- `.local/state/.keep`.

The two marker paths are absent on the pilot. The only collision is the
expected manual `~/.local/bin/codex` symlink. Home Manager is explicitly
configured to take over that same high-precedence launcher; the standalone
0.152.0 release tree stays untouched as rollback input. The existing Codex
configuration already passes Armen's requested relaxed-permission policy, so
the activation reconciler is currently byte-for-byte idempotent. Its dry-run
branch was made strictly non-mutating.

The user Nix profile is empty, no prior Home Manager profile/generation/root
exists, and the installer-created `.nix-profile` link already points at the
expected XDG profile location. Activation does not edit `/etc`, apt, users,
groups, Docker access, GDM, Tailscale, or System Manager. `n0b0dy` is not a
member of the `docker` group; lazydocker adds a client only and grants no daemon
permission. The packaged Devbox binary uses the already managed Nix runtime and
does not invoke Devbox's bootstrap installer during activation.

## One-command transaction

[`scripts/dgx-home`](../scripts/dgx-home) is the operator entry point:

```bash
./scripts/dgx-home status
./scripts/dgx-home preflight
./scripts/dgx-home activate-headless
```

`activate-headless` requires an exact clean commit, rebuilds the scoped checks,
repeats the collision/root/health preflight, and creates a private user-owned
snapshot under `inventory/<host>/private/home-manager-headless/`. Root-owned
System Manager evidence remains isolated under `raw/`. The command name
is the intent signal; there is no confirmation phrase to mistype. Before
activation it arms a ten-minute user-systemd rollback. If activation or
postflight fails, rollback runs immediately; if the terminal disappears, the
timer invokes the snapshot copy. Successful postflight is repeated after the
timer is disarmed and automatically retains the generation.

Rollback removes only the exact first Home generation/profile/root and its
three exact links, then restores the previous Codex launcher and config from
the snapshot. It refuses changed profile or launcher state and preserves a
Codex config changed after activation rather than overwriting new user data.
The disposable [`test-dgx-home-rollback.sh`](../scripts/test-dgx-home-rollback.sh)
test passed against a temporary profile, including exact launcher/config
restoration. The transient timer interface was separately armed and disarmed
without executing its service.

## Remaining live gate

No Home profile was activated while producing this record. Running
`./scripts/dgx-home activate-headless` is the separately visible live user-state
transition. It performs no sudo action and no reboot. On success, the current
shell can immediately resolve the new launcher paths; new login sessions also
inherit the ordinary Nix profile path already installed by the Nix runtime.

The first live invocation failed before snapshot creation or mutation because
the proposed destination was below the deliberately root-owned `raw/` evidence
tree. The user transaction now uses the separate ignored `private/` tree, and
snapshot creation runs outside command substitution so its first error stops
the workflow immediately. No Home profile or timer existed after that failed
invocation.
