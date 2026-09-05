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

  # System Manager deliberately does not implement unit aliases. Supply the
  # default.target alias as a tiny systemd package instead, pointing at the
  # exact generated target unit in the same immutable configuration. The
  # activator then owns the alias through its normal /etc/systemd/system tree
  # and restores the factory /usr/lib default when this role is removed.
  defaultTargetPackage = pkgs.runCommand "dgx-${cfg.mode}-default-target" { } ''
    mkdir -p "$out/lib/systemd/system"
    ln -s \
      '${config.systemd.units.${selectedTargetName}.unit}/${selectedTargetName}' \
      "$out/lib/systemd/system/default.target"
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
    # These are thin orchestration targets. They own no Ubuntu desktop package
    # or display-manager unit. Requiring system-manager.target is essential:
    # System Manager attaches its managed services there, so a headless
    # isolate keeps Nix-managed Tailscale and the root configuration alive on
    # a clean host without depending on an old apt enablement symlink.
    systemd.targets = {
      dgx-headless = {
        description = "DGX headless mode";
        requires = [
          "multi-user.target"
          "system-manager.target"
        ];
        after = [
          "multi-user.target"
          "system-manager.target"
        ];
        conflicts = [
          "dgx-gnome.target"
          "graphical.target"
        ];
        unitConfig.AllowIsolate = true;
      };

      dgx-gnome = {
        description = "DGX factory GNOME mode";
        requires = [
          "graphical.target"
          "system-manager.target"
        ];
        after = [
          "graphical.target"
          "system-manager.target"
        ];
        conflicts = [ "dgx-headless.target" ];
        unitConfig.AllowIsolate = true;
      };
    };

    systemd.packages = [ defaultTargetPackage ];

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
    ];
  };
}
