# Zed package evidence

Date: 2026-09-03 UTC

Host: `sparkle-01`

Result: current ARM64 package and closure policy passed; profile activation and
graphical/Vulkan/portal validation remain open

## Source and ownership

Zed is Armen's selected graphical editor. The package uses the exact official
stable Linux ARM64 bundle rather than the stale locked Nixpkgs package.

- version and tag: `1.18.0` / `v1.18.0`;
- release publication date: 2026-09-02 UTC;
- architecture and asset: `aarch64` / `zed-linux-aarch64.tar.gz`;
- tag commit: `49448afcab82f219b0ef4c58471cf81d23412475`;
- published SHA-256:
  `1e966d0258d0d96c06dd9216f6e1df223c535b6c5e39c7562912bda8481f63c1`;
- SHA-256 SRI: `sha256-HpZtAljQ2WwG3ZIW9uHfIjxTW2xeOcdWKRK9qEgfY8E=`;
- artifact size: 150,878,211 bytes;
- official release: `https://github.com/zed-industries/zed/releases/tag/v1.18.0`;
- package definition: [`packages/zed-editor/default.nix`](../packages/zed-editor/default.nix);
- source record: [`packages/zed-editor/source.json`](../packages/zed-editor/source.json);
- update path: [`scripts/update-zed.sh`](../scripts/update-zed.sh); and
- Nix output:
  `/nix/store/2g9ay7gyr4hp2yvkfdqma234dd39xc62-zed-editor-1.18.0`.

The updater reads GitHub's official latest non-prerelease metadata, verifies
the exact ARM64 asset URL and published digest, resolves the release tag to an
immutable commit, and rejects downgrades or same-version metadata drift. It
does not install, activate, or launch Zed.

## Runtime adapter and factory boundary

[Zed's official Linux contract](https://zed.dev/docs/linux) requires glibc 2.35
or newer, Vulkan 1.3, and desktop portals for file dialogs, URL opening, and
secret storage. The bundle's CLI and editor request
`/lib/ld-linux-aarch64.so.1` and are retained byte-for-byte. The package
therefore deliberately consumes the factory DGX Ubuntu glibc, desktop services,
and NVIDIA Vulkan implementation instead of patching in a parallel graphics
runtime.

The only wrapper change sets Zed's documented `ZED_UPDATE_EXPLANATION`
variable. That disables the application's self-updater and directs updates to
this repository. The official binaries retain SHA-256 values
`79090af63d15303e56405717814dad8a9d0fb475509c6af62cba349247342104`
for the CLI and
`a365bc3b837c094a87f724aa7c0f24d05f69b9bc66aff87fdbdbd920d90b6dcf`
for the editor.

## Closure and side effects

The realized runtime closure is 6 paths / 509,087,728 bytes (485.5 MiB NAR),
of which the package output is 455,805,768 bytes. It contains the editor, CLI,
vendor libraries, icons, licenses, and one desktop entry. It declares no
system or user service, socket, timer, autostart, port, or background server.

The desktop entry advertises text-file and `zed:` URL handlers, but the profile
does not declare MIME defaults. Extensions, language servers, project indexes,
AI-provider credentials, settings, caches, logs, and collaboration state remain
mutable user data outside the Nix store. Zed may fetch extensions/language
servers and use its online services when the user requests those features;
none were fetched during package validation.

## Validation and remaining gate

The exact package and `zed-editor-policy` derivations passed. The policy checks
the immutable source metadata, ARM64 host loader, updater-disable wrapper,
desktop entry, and absence of service/autostart surfaces. With an isolated
empty home, `zed --version` reported exact version `1.18.0` and commit
`49448afcab82f219b0ef4c58471cf81d23412475` without creating state.

Zed remains selected and built but is not in any Home Manager profile. The
remaining gate is a factory-GNOME test of Vulkan rendering, NVIDIA behavior,
file/URL/secret portals, MIME behavior, settings paths, and rollback. Hyprland
and its independently gated portal follow afterward.
