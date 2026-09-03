# LM Studio desktop package evidence

Date: 2026-09-03 UTC

Host: `sparkle-01`

Result: current ARM64 package and closure policy passed; profile activation and
graphical/GB10 validation remain open

## Source and ownership

This is Armen's graphical desktop application, not the
[separate headless `llmster` workload](https://lmstudio.ai/docs/developer/core/headless).
The package pins LM Studio's official Linux ARM64 AppImage directly because
both locked Nixpkgs candidates trailed the vendor release at the time of review.

- version: `0.4.23-1`;
- architecture: `arm64`;
- artifact: `LM-Studio-0.4.23-1-arm64.AppImage`;
- official latest redirect:
  `https://lmstudio.ai/download/latest/linux/arm64`;
- immutable artifact URL:
  `https://installers.lmstudio.ai/linux/arm64/0.4.23-1/LM-Studio-0.4.23-1-arm64.AppImage`;
- SHA-256 SRI: `sha256-MzPygFB0StS8KTuZWq0AR+ZtiQIJ353QHlgpddOa19Y=`;
- artifact size: 1,284,238,985 bytes;
- package definition: [`packages/lmstudio/default.nix`](../packages/lmstudio/default.nix);
- source record: [`packages/lmstudio/source.json`](../packages/lmstudio/source.json);
- update path: [`scripts/update-lmstudio.sh`](../scripts/update-lmstudio.sh); and
- Nix output:
  `/nix/store/539wm7zyckxm30w9ikxj1yja4n02a2z4-lmstudio-0.4.23-1`.

The updater follows only the official Linux ARM64 latest-download redirect,
requires the exact versioned vendor URL shape, rejects downgrades and
same-version URL drift, and hashes the artifact before changing the source
record. It does not install, activate, or launch the application.

## Runtime adapter and factory boundary

The ordinary Nixpkgs AppImage wrapper uses Bubblewrap. On this DGX Ubuntu host,
both system and Nix Bubblewrap fail because
`kernel.apparmor_restrict_unprivileged_userns=1`; changing that host security
policy was neither necessary nor authorized. The package instead extracts the
immutable AppImage and invokes the vendor's `AppRun` with an exact `APPDIR`.

The vendor launcher itself probes `unshare -Ur` and adds Electron's
`--no-sandbox` when the probe fails. That is the current vendor fallback on
this host, but it is a material desktop-runtime security caveat. Before profile
activation, either explicitly accept that behavior for LM Studio or design and
validate a narrow AppArmor/user-namespace alternative. Do not globally weaken
AppArmor merely to launch the application.

Both the Electron executable and bundled `lms` Deno standalone executable
request the factory `/lib/ld-linux-aarch64.so.1` loader. This is deliberate:
the package consumes the DGX Ubuntu desktop/glibc/NVIDIA runtime rather than
introducing a competing graphics stack. `lms` is preserved byte-for-byte;
`patchelf` must not be used on it because appending ELF data destroys Deno's
payload-at-end-of-file marker. Its wrapper supplies only the pinned Nix
`libgcc` runtime.

## Closure and side effects

The realized runtime closure is 9 paths / 2,556,710,256 bytes (2.4 GiB NAR).
The small 311,352-byte package output references the immutable extracted
AppImage, which accounts for nearly all of the closure. It contains launchers,
icons, and one desktop entry; it declares no system or user service, socket,
timer, autostart, port, model, account, or API listener.

The desktop entry advertises the `lmstudio:` URL scheme. A no-display launch
reached Electron through the revised adapter, invoked the vendor application's
`xdg-settings` path, and then stopped at the expected missing-X-server error.
That is launcher evidence, not a graphical pass. A disposable graphical-home
test must inspect URL/MIME changes before activation.

[LM Studio's offline documentation](https://lmstudio.ai/docs/app/offline) says
the Linux application checks the network for available updates at launch and
that an in-app Linux updater is still in progress. No documented disable switch
was found. The immutable Nix package cannot replace itself, but update-check
traffic and any user notification remain to be observed in the graphical test.
Package updates belong to the repository updater, not the app.

Models, runtimes, presets, authentication, chats, caches, and logs remain
mutable user data outside the Nix store. No model was downloaded and no
persistent storage location was selected by this package build.

## Validation and remaining gate

The exact package and `lmstudio-policy` derivations passed. The policy verifies
the source shape, architecture, unfree exception, launchers, host loader,
desktop entry, runtime adapter decisions, and absence of service/autostart
surfaces. In an isolated home, `lms --version` reported CLI commit `07b7252`,
created only `.lmstudio-home-pointer`, and retained SHA-256
`0678cdf4a0293ff929f48bcc52e7b27bbc51182b1375396c69a772f244c58e80`.

LM Studio remains selected and built but is not in any Home Manager profile.
The remaining gate is a factory-GNOME test of Electron launch, NVIDIA/GB10
acceleration, model/runtime storage, portals, URL registration, update checks,
and rollback. Hyprland validation follows separately.
