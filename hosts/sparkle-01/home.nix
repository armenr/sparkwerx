{
  hostSpec,
  userName,
  ...
}:
{
  imports = [
    ../../modules/home/base.nix
    ../../modules/home/admin.nix
    ../../modules/home/desktop.nix
    ../../modules/home/hyprland.nix
    ../../modules/home/user-overlays/armen.nix
  ];

  dgx = {
    # This composes the declared user profile; it is not the still-separate
    # host desktop controller. Factory GNOME/GDM remains running until that
    # root role is designed, reviewed, and explicitly activated.
    desktop = {
      mode = hostSpec.desktop.mode;
      hyprland.portal.enable = hostSpec.desktop.hyprlandPortal;
    };

    # Explicit logical mapping: armen -> n0b0dy@sparkle-01. The selected apps
    # remain absent until their one-at-a-time packaging gates are completed.
    userOverlays.armen = {
      enable = hostSpec.users.armen.overlaySelected;
      graphical.enable = hostSpec.users.armen.graphicalAppsSelected;
      codex.enable = hostSpec.users.armen.codexSelected;
      codex.relaxedPermissions.enable = hostSpec.users.armen.codexRelaxedPermissions;
    };
  };

  assertions = [
    {
      assertion = hostSpec.users.armen.unixName == userName;
      message = "The armen fleet mapping must match this Home Manager user.";
    }
    {
      assertion = hostSpec.fleetBase.enable;
      message = "Every managed fleet user must select the exact fleet base.";
    }
  ];
}
