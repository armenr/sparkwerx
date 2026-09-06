# CUDA-enabled Sunshine build

The same Sunshine release now builds with its Wayland CUDA/GL encoder device
included. Package checks pass. The corrected build has **not yet run against
the pilot GPU**; this does not change the earlier failed startup result.

## What changed

The [local adapter](../../packages/sunshine/README.md) keeps Sunshine
2026.516.143833 and `nixpkgs-apps` revision
`9387b3fcc0c23c86661636da63faabad4235a0a6`. It enables CUDA, rejects a missing
compiler, and preserves the temporary launcher’s factory-driver library path.
No Sunshine source patch or input-lock update was needed.

The approved build dependencies are NVCC 12.9.86, CUDA runtime/headers 12.9.79,
and CCCL headers 12.9.27 from that lock, including its existing CCCL patch.
The earlier inventory incorrectly called this CCCL redistributable free;
its Nix metadata uses the CUDA EULA. Its exact package name is included in the
Sunshine-only allowlist, not the base/general-apps policies.

## Build evidence

The ARM64 build checked both CMake flags, `SUNSHINE_BUILD_CUDA`, the compiled
`cuda.cpp.o` and `cuda.cu.o`, and the defined
`cuda::make_avcodec_gl_encode_device(int, int, int, int)` symbol before stripping.
The package policy passed version-only startup and driver-library-path checks
with the inherited path absent, empty, and populated. It rejected CUDA stubs
and compiler directories in the ELF runtime search path.

- Sunshine derivation: `/nix/store/wmp739qp32a875mh6j1a6zymmc30xvw2-sunshine-2026.516.143833.drv`
- Sunshine output: `/nix/store/3j2b6777c4i5kvikzw4ghfjz6qmfhafj-sunshine-2026.516.143833`
- Package policy: `/nix/store/adqxs16r37ccsl8hn438dfm6wp95iyn5-sparkwerx-sunshine-build-policy`
- Temporary startup bundle: `/nix/store/lw0w4vv7h0vbbas4yq6sn2qsq7b1n53b-dgx-remote-desktop-sunshine-startup-test`
- Startup isolation/config policy: `/nix/store/m5mwxa23cqzvhjx614w963yv1rymqrd5-sparkwerx-private-session-policy`
- Capture-only isolation/config policy: `/nix/store/y8j76w94g600yql86jp53s1smril5k4a-sparkwerx-private-session-policy`

Both session policies passed their 53-test suites and all three Hyprland config
parses. Both skipped the factory systemd parser check, unavailable inside the
Nix build sandbox. Capture-only additionally skipped the Sunshine parser check;
the Sunshine variant ran it against the rebuilt binary. These are offline
tests, not a GPU launch. `./scripts/dev check` also passed all lint/evaluation
checks and its 134-test suite, with two optional parser checks skipped.

## Dependency size

The new output is 25,329,392 bytes (24.2 MiB); its complete runtime closure is
833,623,408 bytes (795.0 MiB). The stock build was 22.8 MiB with a 793.6 MiB
closure. Both have 235 store paths. Comparing the path sets changes only the
Sunshine output itself: the increase is 1,445,512 bytes, about 1.4 MiB.

No separate CUDA compiler, CUDA redistributable, or Nix NVIDIA driver occurs
in the resulting runtime closure. Build dependencies occupy additional Nix
store space but are not deployed runtime dependencies. No active Home/root
profile, factory package, service, device permission, or boot setting changed.

## Next check

Run `./scripts/test-remote-desktop-sunshine.sh` from the checkout as the normal
user; sudo is requested only for the existing temporary GPU session. The
150-second service limit, private state, input denial, TCP/UDP denial, and host
postflight are unchanged. KMS must still be enabled on the current boot.
Encoder startup, changing-frame capture, and actual streaming remain separate
results; no persistent server or reboot is part of this build.
