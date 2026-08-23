{ config, lib, ... }:
let
  cfg = config.dgx.admin;
in
{
  options.dgx.admin = {
    homeManagerCli.enable = lib.mkEnableOption "the Home Manager command-line interface";
    manpages.enable = lib.mkEnableOption "Home Manager's man viewer and generated configuration manpage";
  };

  config = {
    programs.home-manager.enable = cfg.homeManagerCli.enable;
    programs.man.enable = cfg.manpages.enable;
    programs.man.man-db.enable = cfg.manpages.enable;
    manual.manpages.enable = cfg.manpages.enable;
  };
}
