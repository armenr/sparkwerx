{
  config,
  lib,
  pkgs,
  hyprlandPackage,
  hyprlandPortalPackage,
  ...
}:
let
  cfg = config.dgx.desktop.hyprland;
  modeSelected = config.dgx.desktop.mode == "hyprland";
in
{
  options.dgx.desktop.hyprland.portal.enable =
    lib.mkEnableOption "the independently reviewed Hyprland and GTK portal closure";

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !cfg.portal.enable || modeSelected;
          message = "The Hyprland portal can be enabled only when dgx.desktop.mode is \"hyprland\".";
        }
      ];
    }

    (lib.mkIf modeSelected {
      # Home Manager owns only the user compositor configuration. The future
      # non-NixOS graphics bridge and GDM session entry stay host-level.
      wayland.windowManager.hyprland = {
        enable = true;
        package = hyprlandPackage;
        systemd.enable = false;

        # Home Manager otherwise enables the portal implicitly. Keep it null so
        # the independently approved option below is the only portal gate.
        portalPackage = null;
      };
    })

    (lib.mkIf (modeSelected && cfg.portal.enable) {
      xdg.portal = {
        # The upstream Hyprland module sets this false when portalPackage is
        # null, so the explicit independent gate must take precedence.
        enable = lib.mkForce true;
        extraPortals = [
          hyprlandPortalPackage
          pkgs.xdg-desktop-portal-gtk
        ];
        config.hyprland.default = [
          "hyprland"
          "gtk"
        ];
      };
    })
  ];
}
