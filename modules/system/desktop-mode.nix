{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.dgx.root.desktop;
  supportedModes = [
    "headless"
    "gnome"
  ];
  selectedTargetName = "dgx-${cfg.mode}.target";

  headlessTargetPackage = pkgs.writeTextDir "lib/systemd/system/dgx-headless.target" ''
    [Unit]
    Description=DGX headless mode
    Requires=multi-user.target system-manager.target
    After=multi-user.target system-manager.target
    # The factory Dashboard UI is independently wanted by default.target. A
    # conflict is required so it cannot start alongside a headless default
    # boot; the separate Dashboard admin daemon remains in multi-user.target.
    Conflicts=dgx-dashboard.service dgx-gnome.target graphical.target
    AllowIsolate=true
  '';

  gnomeTargetPackage = pkgs.writeTextDir "lib/systemd/system/dgx-gnome.target" ''
    [Unit]
    Description=DGX factory GNOME mode
    Requires=graphical.target system-manager.target
    After=graphical.target system-manager.target
    Conflicts=dgx-headless.target
    AllowIsolate=true
  '';

  # System Manager deliberately does not implement unit aliases: immutable
  # unit links outside systemd's search path retain the lookup name
  # `default.target` instead of becoming a real alias to the selected target.
  # Supply a tiny dispatcher unit that explicitly requires the selected named
  # target. It remains outside System Manager's active service set, so merely
  # activating a declaration does not isolate or switch the running desktop.
  # Removing the role restores the factory /usr/lib default.
  defaultTargetPackage = pkgs.writeTextDir "lib/systemd/system/default.target" ''
    [Unit]
    Description=DGX ${cfg.mode} boot dispatcher
    Requires=${selectedTargetName}
    After=${selectedTargetName}
  '';
in
{
  options.dgx.root.desktop = {
    enable = lib.mkEnableOption ''
      the reviewed non-NixOS headless/factory-GNOME target controller
    '';

    mode = lib.mkOption {
      type = lib.types.enum supportedModes;
      default = "gnome";
      description = ''
        Persistent host boot/runtime target selected by the root controller.
        This first implementation intentionally supports only headless and the
        factory GNOME stack; Hyprland and KDE remain independent later gates.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # These are thin orchestration files, not System Manager-managed active
    # services. The future guarded desktop operator owns runtime isolation;
    # activation only changes persistent declaration. Keeping them out of the
    # service set also lets controller removal discard an inactive alternate
    # target without System Manager trying to stop an already-unloaded unit.
    # Requiring system-manager.target is essential: System Manager attaches
    # its managed services there, so a headless isolate keeps Nix-managed
    # Tailscale and the root configuration alive on a clean host without
    # depending on an old apt enablement symlink.
    systemd.packages = [
      defaultTargetPackage
      headlessTargetPackage
      gnomeTargetPackage
    ];

    environment.etc."dgx-setup/desktop-mode" = {
      text = ''
        schema=1
        owner=DGX-setup
        mode=${cfg.mode}
        runtime-target=${selectedTargetName}
        factory-display-manager=gdm.service
        factory-desktop-packages-preserved=true
      '';
      replaceExisting = false;
    };

    assertions = [
      {
        assertion = builtins.elem cfg.mode supportedModes;
        message = "The first DGX root desktop controller supports only headless and gnome.";
      }
      {
        assertion = !builtins.hasAttr "gdm.service" config.systemd.units;
        message = "The DGX desktop controller must orchestrate, not own, factory GDM.";
      }
      {
        assertion = !builtins.hasAttr "display-manager.service" config.systemd.units;
        message = "The DGX desktop controller must not replace the factory display-manager alias.";
      }
      {
        assertion = !builtins.hasAttr "dgx-dashboard.service" config.systemd.units;
        message = "The DGX desktop controller must orchestrate, not own, the factory Dashboard GUI.";
      }
      {
        assertion = !builtins.hasAttr "dgx-dashboard-admin.service" config.systemd.units;
        message = "The DGX desktop controller must not own the headless-safe factory Dashboard admin daemon.";
      }
    ];
  };
}
