{
  config,
  lib,
  pkgs,
  ...
}:

let
  forbiddenUnitNames = [
    "docker.service"
    "gdm.service"
    "nix-daemon.service"
  ];

  unitIsInactive =
    name: !(builtins.hasAttr name config.systemd.units) || !config.systemd.units.${name}.enable;
in
{
  imports = [
    ./boot-persistence.nix
    ./tailscale.nix
  ];

  # System Manager imports several broad NixOS-derived modules. Every default
  # below is deliberately narrowed so the first root closure is only a canary,
  # not accidental ownership of users, Nix, global PATH, or setuid wrappers.
  nix.enable = false;
  services.userborn.enable = false;
  # Upstream's deactivation script puts this package on PATH unconditionally.
  # With user ownership forbidden, retain an empty bin directory instead of the
  # otherwise unused userborn runtime closure.
  services.userborn.package = lib.mkForce (
    pkgs.runCommand "disabled-userborn" { } ''
      mkdir -p "$out/bin"
    ''
  );
  security.enableWrappers = false;

  system-manager = {
    allowAnyDistro = false;
    linkCurrentSystem = false;
  };

  # Root packages do not belong in the System Manager layer. User tools remain
  # in Home Manager's exact three-package fleet base.
  environment.systemPackages = lib.mkForce [ ];

  # These upstream defaults would otherwise alter every login environment even
  # with an empty package list. They are outside this canary's approval scope.
  environment.etc = {
    "profile.d/system-manager-path.sh".enable = lib.mkForce false;
    "environment.d/10-system-manager.conf".enable = lib.mkForce false;
    "tmpfiles.d".enable = lib.mkForce false;
  };
  systemd.services.system-manager-path.enable = lib.mkForce false;

  assertions = [
    {
      assertion = !config.nix.enable;
      message = "The DGX root manager must not own the nix-installer configuration.";
    }
    {
      assertion = !config.services.userborn.enable;
      message = "The DGX root canary must not own users, groups, passwd, or shadow.";
    }
    {
      assertion = config.services.userborn.package.name == "disabled-userborn";
      message = "The inert canary must not retain userborn in its runtime closure.";
    }
    {
      assertion = !config.security.enableWrappers;
      message = "The DGX root canary must not add setuid wrappers or a wrapper mount.";
    }
    {
      assertion = config.environment.systemPackages == [ ];
      message = "The DGX System Manager layer must not add global system packages.";
    }
    {
      assertion = !config.system-manager.linkCurrentSystem;
      message = "The inert canary must not claim /run/current-system.";
    }
    {
      assertion = lib.all unitIsInactive forbiddenUnitNames;
      message = "The DGX root role must not declare Nix, GDM, or Docker units.";
    }
  ];
}
