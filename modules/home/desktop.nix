{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dgx.desktop;
  isGraphical = cfg.mode != "headless";
in
{
  options = {
    dgx.desktop = {
      mode = lib.mkOption {
        type = lib.types.enum [
          "headless"
          "gnome"
          "hyprland"
          "kde"
        ];
        default = "headless";
        description = ''
          Desired DGX desktop mode. At this phase the option composes only the
          Home Manager user profile; it cannot stop GDM or switch the host's
          systemd target until the separately reviewed root controller exists.
        '';
      };

      isGraphical = lib.mkOption {
        type = lib.types.bool;
        readOnly = true;
        internal = true;
        description = "Whether the selected desktop mode is graphical";
      };
    };

    dgx.sharedGraphical.packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      readOnly = true;
      internal = true;
      description = "Packages shared by every graphical desktop mode";
    };
  };

  config = {
    dgx.desktop.isGraphical = isGraphical;

    # XDG base-directory and shared MIME-database ownership are graphical.
    # Default applications, user directories, and portals remain independent.
    xdg.enable = isGraphical;
    xdg.mime.enable = isGraphical;
    xdg.mimeApps.enable = lib.mkDefault false;
    xdg.userDirs.enable = lib.mkDefault false;
    xdg.portal.enable = lib.mkDefault false;

    dgx.sharedGraphical.packages = lib.optionals isGraphical [ pkgs.ghostty ];
    home.packages = config.dgx.sharedGraphical.packages;
  };
}
