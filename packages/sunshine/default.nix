{
  lib,
  sunshine,
  cudaPackages,
  binutils,
}:
let
  cudaSunshine = sunshine.override { cudaSupport = true; };
  evidence = {
    sunshineVersion = sunshine.version;
    cudaCompilerVersion = cudaPackages.cuda_nvcc.version;
    cudaRuntimeVersion = cudaPackages.cuda_cudart.version;
    cudaImplementationCompiled = true;
    streamingTested = false;
  };
in
# This is a build-option/wrapper adapter, not an upstream version override.
# Review the source, toolchain, and startup verifier together when updating.
assert sunshine.version == "2026.516.143833";
assert cudaPackages.cuda_nvcc.version == "12.9.86";
assert cudaPackages.cuda_cudart.version == "12.9.79";
assert cudaPackages.cccl.version == "12.9.27";
cudaSunshine.overrideAttrs (old: {
  cmakeFlags = old.cmakeFlags ++ [
    (lib.cmakeBool "SUNSHINE_ENABLE_CUDA" true)
    (lib.cmakeBool "CUDA_FAIL_ON_MISSING" true)
  ];

  # Codec names alone also appear in CUDA-disabled binaries. Check both the
  # generated build configuration and the actual CUDA objects/defined symbol.
  postConfigure = (old.postConfigure or "") + ''
    grep -Fx 'SUNSHINE_ENABLE_CUDA:BOOL=TRUE' CMakeCache.txt
    grep -Fx 'CUDA_FAIL_ON_MISSING:BOOL=TRUE' CMakeCache.txt
    grep -E '^CXX_DEFINES = .*[-]DSUNSHINE_BUILD_CUDA([ =]|$)' CMakeFiles/sunshine.dir/flags.make
  '';
  postBuild = (old.postBuild or "") + ''
    test -s CMakeFiles/sunshine.dir/src/platform/linux/cuda.cpp.o
    test -s CMakeFiles/sunshine.dir/src/platform/linux/cuda.cu.o
    ${lib.getExe' binutils "nm"} --defined-only --demangle sunshine \
      | grep -F 'cuda::make_avcodec_gl_encode_device('
  '';
  postInstall = (old.postInstall or "") + ''
    mkdir -p "$out/share/sparkwerx"
    printf '%s\n' '${builtins.toJSON evidence}' > "$out/share/sparkwerx/sunshine-build.json"
  '';

  # The locked CUDA-enabled recipe overwrites LD_LIBRARY_PATH with Vulkan.
  # Prepend that same Nix loader instead, retaining the launcher's private,
  # reviewed factory-driver bridge. Never add all of Ubuntu's /usr/lib here.
  postFixup =
    assert lib.hasInfix "--set LD_LIBRARY_PATH " old.postFixup;
    builtins.replaceStrings [ "--set LD_LIBRARY_PATH " ] [ "--prefix LD_LIBRARY_PATH : " ]
      old.postFixup;

  # Build tools must not become part of the deployed application's closure.
  disallowedRequisites = (old.disallowedRequisites or [ ]) ++ [ cudaPackages.cuda_nvcc ];
  passthru = (old.passthru or { }) // {
    sparkwerxBuild = evidence;
  };
})
