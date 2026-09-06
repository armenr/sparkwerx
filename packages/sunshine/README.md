# Sunshine on the Spark

This is a small adapter around the locked Nixpkgs package, not a separate flake
or a Sunshine fork. It keeps the upstream version and source hashes.

## Why the adapter exists

The stock package disables CUDA. In Sunshine 2026.516.143833, that also removes
the CUDA/GL encoder device used by its Wayland capture backend. The separate
FFmpeg NVENC test can pass while this Sunshine binary cannot initialize it.
See the [failed startup investigation](../../remote-desktop/validation/2026-09-06-sunshine-startup-failure.md).

[default.nix](default.nix) enables CUDA and makes a missing CUDA compiler fatal.
It checks the generated build flags, CUDA object files, and defined encoder
factory symbol before writing build evidence. It also changes the Nix wrapper
to prepend its Vulkan loader path instead of overwriting the temporary
session's factory-driver library path.

The isolated [package configuration](config.nix) permits exactly the required
`cuda_nvcc`, `cuda_cudart`, and `cuda_cccl` packages. CCCL is a header dependency;
the locked NVIDIA redistributable is also marked with the CUDA EULA in Nixpkgs.
The compiler must not appear in Sunshine's runtime closure. Nothing here
replaces the factory driver or system CUDA, or installs a persistent service.

## Build and check

From the repository root, as the normal user:

```bash
nix build --no-link .#sunshine .#sunshine-policy
```

The package policy tests the resulting binary's loader paths and version-only
startup with an absent, empty, and existing driver-library path. It opens no
GPU or listener. The [temporary GPU diagnostic](../../docs/remote-desktop.md#temporary-sunshine-startup-test)
is a separate test; compilation is not proof of working capture or streaming.

The private session must also expose the factory `/dev/nvidia-uvm` device.
Hiding it [reproduces `CUDA_ERROR_UNKNOWN` at initialization](../../remote-desktop/validation/2026-09-06-sunshine-uvm-device.md),
even with a correctly compiled package. Fix that session prerequisite, not the
driver or Sunshine source. The diagnostic checks for the existing node and
does not create it or change its permissions.

Its CUDA/GL path also opens the GPU's primary DRM card directly, unlike
Hyprland's brokered access. The diagnostic's [temporary child groups](../../remote-desktop/validation/2026-09-07-sunshine-drm-access.md)
must include that card's group as well as the render node's group. Missing
card access is a session permission error, not a reason to patch Sunshine,
run it as root, or change host device permissions.

## Offline capture diagnostic

[capture-test.nix](capture-test.nix) is a separate executable for the
[changing-frame test](../../docs/remote-desktop.md#temporary-sunshine-changing-frame-test),
not a replacement for the Sunshine package. It reuses this CUDA recipe but
replaces only `src/main.cpp` with [capture-main.cpp](capture-main.cpp).
[Source checksums](capture-engine.sha256) pin the unchanged video, Wayland, and
CUDA engines. The entry point consumes real `video::capture()` packets into
temporary elementary streams without initializing servers, input, or audio.

The diagnostic output installs no `sunshine` command, service, or udev rule.
Its inert `--describe` branch is checked during the build. The normal package's
[startup hardware run passed](../../remote-desktop/validation/2026-09-07-sunshine-startup-host.md);
the separate changing-frame executable still needs its own hardware result.

## Updating it

1. Review the stable Sunshine release and the `nixpkgs-apps` input together.
   The source and CUDA archives come from that input's existing hashes.
2. Inspect Nixpkgs' `pkgs/by-name/su/sunshine/package.nix`, CUDA dependencies,
   and wrapper, plus Sunshine's versioned `cmake/compile_definitions/linux.cmake`
   and `src/platform/linux/{wlgrab,cuda}.cpp`. Check the actual build and capture
   code, not codec-name strings in the executable.
3. Update the explicit version assertions and evidence expectations only after
   that review. Keep missing CUDA a build error. Review the runtime closure and
   preserve the factory-driver bridge; don't enable all unfree packages.
4. Run the package policy, repository checks, and temporary GPU startup test.
   Changing-frame capture, client pairing, and stream performance need their
   own tests before deployment.
5. Review the diagnostic entry point against the new `video::capture()` API
   and packet-replacement semantics before updating its source checksums.
   Retest CPU decoding fixtures and the hardware capture command separately;
   never remove the source check just to make an update build.

Remove an override when the locked upstream package supplies the same behavior
and the checks still pass. If a real source patch becomes necessary, keep it
next to this recipe, add it through Nix's `patches` attribute, and document its
upstream issue or commit and removal condition. Never edit built store files.

- [Locked Nixpkgs recipe](https://github.com/NixOS/nixpkgs/blob/9387b3fcc0c23c86661636da63faabad4235a0a6/pkgs/by-name/su/sunshine/package.nix)
- [Sunshine CUDA build configuration](https://github.com/LizardByte/Sunshine/blob/v2026.516.143833/cmake/compile_definitions/linux.cmake)
- [Sunshine Wayland capture implementation](https://github.com/LizardByte/Sunshine/blob/v2026.516.143833/src/platform/linux/wlgrab.cpp)
