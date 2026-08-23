{
  appsPkgs,
  config,
  lib,
  pkgs,
  ...
}:
{
  options.dgx.fleetBase.packages = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    readOnly = true;
    internal = true;
    description = "The exact permanent fleet CLI package set";
  };

  config = {
    # Keep these defaults minimal even if this module is reused without the
    # administrative role. That role can deliberately override them.
    programs.home-manager.enable = lib.mkDefault false;
    programs.man.enable = lib.mkDefault false;
    programs.man.man-db.enable = lib.mkDefault false;
    manual.manpages.enable = lib.mkDefault false;

    # Permanent fleet base: do not add convenience tools here. Devbox is taken
    # from the separately locked apps package set; this installs the packaged Go
    # binary and never invokes Devbox's Nix bootstrap installer.
    dgx.fleetBase.packages = [
      pkgs.ncdu
      pkgs.lazydocker
      appsPkgs.devbox
    ];

    home.packages = config.dgx.fleetBase.packages;
  };
}
