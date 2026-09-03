# Codex CLI package evidence

Date: 2026-09-03 UTC

Host: `sparkle-01`

Result: current package and every-profile composition passed; activation open

## Source and ownership

Official OpenAI documentation lists the standalone installer and npm as the
supported Linux installation paths. The standalone installer prefers the full
release bundle from `releases.openai.com`; this package pins that same bundle
directly rather than executing the mutable installer.

- version: 0.153.0;
- release tag: `rust-v0.153.0`;
- target: `aarch64-unknown-linux-musl`;
- asset: `codex-package-aarch64-unknown-linux-musl.tar.gz`;
- published SHA-256:
  `076b2b7512bad8b96e24370c031d2d1311f983e98650af9824639a619fa99be4`;
- source: `https://releases.openai.com/codex/releases/0.153.0/`;
- Nix output:
  `/nix/store/wdrv0fcgn8k7pvl0a69mp3sri7b1szpq-codex-cli-0.153.0`; and
- closure: one path, 278.2 MiB NAR.

`scripts/update-codex.sh` reads OpenAI's stable release channel, validates the
final semantic release tag, compares channel metadata with the package checksum
manifest, rejects downgrades and same-version digest drift, and changes only
the exact source record in apply mode. The main dependency updater invokes this
path and then rebuilds the package and all profiles.

## Validation

The pinned bundle contains exactly the expected top-level executable payload:

- `bin/codex`;
- `bin/codex-code-mode-host`;
- `codex-path/rg`;
- `codex-resources/bwrap`; and
- `codex-package.json`.

All three binaries are static ARM64 ELF executables. The bundled ripgrep reports
15.2.0, the package manifest reports layout 1/version 0.153.0/the exact target,
and both normal and strict-config version checks report `codex-cli 0.153.0`.
The package policy and permission-reconciler regression derivations passed.

Codex is present in the evaluated headless, GNOME, Hyprland, and
Hyprland-with-portal Home profiles. The profile policy proves it remains in
Armen's named overlay rather than the three-package fleet base. Home Manager
will own `~/.local/bin/codex`, which intentionally replaces only the current
standalone launcher's symlink because that path precedes the Nix profile in the
pilot's `PATH`.

No Home profile or launcher was activated. The current standalone 0.152.0
release tree remains untouched for rollback, and mutable authentication,
plugins, MCP servers, project trust, desktop state, and history were neither
read into the Nix store nor replaced. The narrow live reconciler did set
`check_for_update_on_startup = false`; both the retained 0.152.0 binary and the
packaged 0.153.0 binary accept the resulting config in strict mode.
