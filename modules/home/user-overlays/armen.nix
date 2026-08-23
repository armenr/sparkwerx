{ config, lib, ... }:
let
  cfg = config.dgx.userOverlays.armen;
in
{
  options.dgx.userOverlays.armen = {
    enable = lib.mkEnableOption "Armen's explicitly mapped personal overlay";

    graphical = {
      enable = lib.mkEnableOption "Armen's selected graphical application set";

      active = lib.mkOption {
        type = lib.types.bool;
        readOnly = true;
        internal = true;
        description = "Whether Armen's graphical overlay is active in the selected mode";
      };
    };
  };

  config = {
    assertions = [
      {
        assertion = !cfg.graphical.enable || cfg.enable;
        message = "Armen's graphical overlay requires dgx.userOverlays.armen.enable.";
      }
    ];

    # Selection persists while headless, but packages and graphical state enter
    # the profile only in a graphical mode. Applications are added one at a
    # time after their individual manifest and closure reviews.
    dgx.userOverlays.armen.graphical.active =
      cfg.enable && cfg.graphical.enable && config.dgx.desktop.isGraphical;
  };
}
