{
  pkgs,
  sunshine,
  vulkan-loader,
}:
let
  inherit (pkgs) lib;
  policy = import ./config.nix { inherit lib; };
  permits = pname: policy.allowUnfreePredicate { inherit pname; };
in
assert !policy.allowUnfree;
assert lib.all permits [
  "cuda_nvcc"
  "cuda_cudart"
  "cuda_cccl"
];
assert lib.all (name: !permits name) [
  "cuda_compat"
  "cudnn"
  "nvidia-x11"
  "lmstudio"
  "vscode"
];
pkgs.runCommand "sparkwerx-sunshine-build-policy"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    mkdir -p "$out"
    python3 ${./test-package.py} \
      --package ${sunshine} \
      --bash ${pkgs.bash}/bin/bash \
      --patchelf ${pkgs.patchelf}/bin/patchelf \
      --vulkan-lib ${lib.makeLibraryPath [ vulkan-loader ]}
    cp ${sunshine}/share/sparkwerx/sunshine-build.json "$out/build.json"
    touch "$out/passed"
  ''
