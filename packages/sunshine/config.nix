{ lib }:
{
  # Only the Sunshine package set imports this configuration. Neither the
  # fleet base nor the general apps set gains these exceptions.
  allowUnfree = false;
  allowUnfreePredicate =
    package:
    builtins.elem (lib.getName package) [
      "cuda_nvcc"
      "cuda_cudart"
      # Required CUDA runtime headers; the locked redistributable's Nix
      # metadata also marks these as covered by the CUDA EULA.
      "cuda_cccl"
    ];
}
