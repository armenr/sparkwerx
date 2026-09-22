# Sunshine startup: missing CUDA build support

The first Sunshine startup attempt reached the 3840×2160 Wayland display but
did not initialize H.264, HEVC, or AV1. Host cleanup/postflight passed. This is
a package-build problem to resolve before another GPU test, not evidence that
GB10 lacks NVENC or that headless mode must be abandoned.

## Evidence

Armen supplied the failed run and the read-only inspector's redacted output:

- Checkout: `b618bd1`.
- Private snapshot: `inventory/sparkle-01/raw/remote-desktop-session/20260906T192101Z-a64914fe0711`.
- Sunshine: `/nix/store/l6phapr6sk3y3q3bdv0m19r8dm78s5yb-sunshine-2026.516.143833`.
- Derivation: `/nix/store/8az9lh584kwgs3jqq69vq292jmsgpl0g-sunshine-2026.516.143833.drv`.
- Test bundle: `/nix/store/msvfpmyfv4n7pxj9jq34nd2m7g8g5682-dgx-remote-desktop-sunshine-startup-test`.

The inspector saw the seat broker, NVIDIA compositor, Wayland backend, expected
dimensions, and encoder fallback failures. It reported all three final NVENC
success messages missing. The socket-family rejection is expected: this test
denies TCP/UDP. Do not open ports or grant input access to address it.

The original 40-line tail excerpt omitted the first encoder attempt. The
updated inspector keeps both ends of the redacted Sunshine excerpt and reports
omissions. It can inspect this same snapshot without starting a GPU session or
changing evidence permissions. The agent did not read the root-private raw log;
sudo required the operator's password.

Independent read-only inspection found systemd running and the selected root
still `/nix/store/djp7ap9gc7kq6c5hhbqzzslvmg4vq3m1-system-manager`.
The earlier [Grim capture PASS](2026-09-06-temporary-capture-host.md) and
[one-boot KMS trial](../../root/graphics/validation/2026-09-06-kms-test-boot.md)
remain separate evidence. No reboot or permanent KMS change was performed.

## Confirmed package mismatch

The exact derivation's structured build attributes contain
`-DSUNSHINE_ENABLE_CUDA:BOOL=FALSE`. The locked
[Nixpkgs recipe](https://github.com/NixOS/nixpkgs/blob/9387b3fcc0c23c86661636da63faabad4235a0a6/pkgs/by-name/su/sunshine/package.nix)
sets this when CUDA support is not requested.

In this Sunshine release, its
[Linux build configuration](https://github.com/LizardByte/Sunshine/blob/v2026.516.143833/cmake/compile_definitions/linux.cmake)
only compiles the CUDA implementation and defines `SUNSHINE_BUILD_CUDA` when a
CUDA compiler is enabled and found. The
[Wayland backend](https://github.com/LizardByte/Sunshine/blob/v2026.516.143833/src/platform/linux/wlgrab.cpp)
puts its CUDA/GL encoder-device factory behind that definition. Our stock
binary therefore lacks a required part of this capture/encoder path.
Codec names in the binary, a successful config parser, or separate FFmpeg
NVENC tests cannot establish that Sunshine's own implementation is present.
Further runtime problems may become visible only after a corrected build.

## Next package change

The proposed same-release CUDA override adds `cuda_nvcc` 12.9.86 and
`cuda_cudart` 12.9.79 from the existing apps lock, plus their dependencies.
Nix refuses evaluation at `cuda_cudart` under our current unfree predicate.
The [software manifest](../../docs/software-manifest.md#optional-remote-desktop)
records this proposal; it is not an approved exception or a realized build.

After dependency approval, the adapter needs to require CUDA explicitly and
fail configuration if the compiler is missing, then verify the compiled CUDA
path. Also review the CUDA-enabled recipe's wrapper: it sets `LD_LIBRARY_PATH`
to the Vulkan loader, which would overwrite this test's narrow factory-driver
bridge. Preserve that bridge without exposing all host libraries. Inspect the
actual build/runtime closure before realization; no system CUDA, driver,
profile, permissions, service, or network change is part of this repair.

The front door now checks the required build flags before building the GPU
bundle or requesting sudo. That prerequisite is not a claim of successful
compilation or hardware operation. `inspect` bypasses it because inspection
does not run Sunshine. A corrected build must pass the isolated startup test
before work proceeds to real Sunshine frame capture and Moonlight transport.

## Diagnostic repair checks

- `./scripts/dev check` passed: lint/format, 134 Python tests (two optional
  checks run in their Nix policy builds), documentation, and flake evaluation.
- Both private-session policy builds passed 53 tests and all three Hyprland
  config parses. The Sunshine variant also exercised the real config parser,
  without initializing graphics. Its one skip is factory systemd parsing,
  which the normal repository test suite exercises.
- The actual front door rejected the unchanged stock build before sudo.
  Command-double tests also cover failed/malformed evaluation, the compatible
  metadata route, and read-only inspection bypassing the GPU prerequisite.
- Inspector: `/nix/store/fjfy5770n7myma9k1ia5bn513gnwj1qa-dgx-remote-desktop-session-inspect`.
- Capture policy: `/nix/store/sgxm2icqh0bym29g8v0izr3g6mzg5y0r-sparkwerx-private-session-policy`.
- Sunshine policy: `/nix/store/qm6wnr267wkrlwk08w0vknpspa7b43zn-sparkwerx-private-session-policy`.

These repairs required no new third-party download or hardware retry. Headless
and KMS-trial package outputs evaluated to the same existing store paths.
