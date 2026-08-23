{
  config,
  lib,
  pkgs,
  hyprlandPackage,
  hyprlandPortalPackage,
  ...
}:
let
  cfg = config.dgx.hyprland;
in
{
  options.dgx.hyprland.enable = lib.mkEnableOption "the DGX Hyprland pilot";

  config = lib.mkIf cfg.enable {
    # Home Manager owns the user configuration. The non-NixOS graphics bridge,
    # desktop portals, and GDM session entry are host-level concerns and will be
    # added only after the pilot plan is reviewed.
    wayland.windowManager.hyprland = {
      enable = true;
      package = hyprlandPackage;
      portalPackage = hyprlandPortalPackage;
    };
  };
}
