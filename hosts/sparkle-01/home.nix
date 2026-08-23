{ ... }:
{
  imports = [
    ../../modules/home/base.nix
    ../../modules/home/hyprland.nix
  ];

  # This remains false until the non-NixOS NVIDIA/GDM pilot and rollback path
  # have been reviewed.
  dgx.hyprland.enable = false;
}
