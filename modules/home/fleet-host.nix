{
  hostSpec,
  userName,
  ...
}:
{
  imports = [
    ./base.nix
    ./admin.nix
    ./desktop.nix
    ./hyprland.nix
    ./user-overlays/armen.nix
  ];

  # This is the default user composition for every declared DGX. A host may
  # still grow an explicit hosts/<name>/home.nix when it truly needs a
  # host-specific override, but a normal fleet addition needs only the data in
  # fleet/hosts.json.
  dgx = {
    desktop = {
      mode = hostSpec.desktop.mode;
      hyprland.portal.enable = hostSpec.desktop.hyprlandPortal;
    };

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
