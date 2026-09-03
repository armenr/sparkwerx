{ ... }:
{
  imports = [
    ../../modules/home/base.nix
    ../../modules/home/admin.nix
    ../../modules/home/desktop.nix
    ../../modules/home/hyprland.nix
    ../../modules/home/user-overlays/armen.nix
  ];

  dgx = {
    # This is the conservative user-profile staging mode, not a host mutation.
    # Factory GNOME/GDM remains running until a root controller is separately
    # designed, reviewed, and explicitly activated.
    desktop.mode = "headless";

    # Explicit logical mapping: armen -> n0b0dy@sparkle-01. The selected apps
    # remain absent until their one-at-a-time packaging gates are completed.
    userOverlays.armen = {
      enable = true;
      graphical.enable = true;
      codex.enable = true;
      codex.relaxedPermissions.enable = true;
    };
  };
}
