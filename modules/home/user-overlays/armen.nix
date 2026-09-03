{
  config,
  codexPackage,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dgx.userOverlays.armen;
  codexRelaxedDefaultsReconciler = pkgs.writeShellApplication {
    name = "dgx-reconcile-codex-relaxed-defaults";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
    ];
    text = builtins.readFile ../../../scripts/reconcile-codex-relaxed-defaults.sh;
  };
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

    codex = {
      enable = lib.mkEnableOption "the Nix-managed Codex CLI in every desktop mode";

      active = lib.mkOption {
        type = lib.types.bool;
        readOnly = true;
        internal = true;
        description = "Whether Armen's Nix-managed Codex CLI is active";
      };

      packages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        readOnly = true;
        internal = true;
        description = "Armen's exact all-modes Codex package set";
      };

      relaxedPermissions = {
        enable = lib.mkEnableOption "Armen's deliberately unrestricted Codex session defaults";

        active = lib.mkOption {
          type = lib.types.bool;
          readOnly = true;
          internal = true;
          description = "Whether Armen's permissive Codex defaults are reconciled at Home Manager activation";
        };

        policy = lib.mkOption {
          type = lib.types.attrs;
          readOnly = true;
          internal = true;
          description = "The exact non-secret Codex settings owned by Armen's overlay";
        };
      };
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !cfg.graphical.enable || cfg.enable;
          message = "Armen's graphical overlay requires dgx.userOverlays.armen.enable.";
        }
        {
          assertion = !cfg.codex.enable || cfg.enable;
          message = "Armen's Codex package requires dgx.userOverlays.armen.enable.";
        }
        {
          assertion = !cfg.codex.relaxedPermissions.enable || cfg.enable;
          message = "Armen's Codex policy requires dgx.userOverlays.armen.enable.";
        }
      ];

      # Selection persists while headless, but packages and graphical state enter
      # the profile only in a graphical mode. Applications are added one at a
      # time after their individual manifest and closure reviews.
      dgx.userOverlays.armen.graphical.active =
        cfg.enable && cfg.graphical.enable && config.dgx.desktop.isGraphical;

      # Codex is useful in every desktop mode. This manages only permission and
      # approval defaults; Codex/ChatGPT continue to own auth, plugins, MCP
      # servers, model selection, history, and other mutable preferences.
      dgx.userOverlays.armen.codex.relaxedPermissions.active =
        cfg.enable && cfg.codex.relaxedPermissions.enable;
      dgx.userOverlays.armen.codex.relaxedPermissions.policy = {
        approval_policy = "never";
        default_permissions = ":danger-full-access";
        approvals_reviewer = "auto_review";
        check_for_update_on_startup = false;
        notice.hide_full_access_warning = true;
        apps._default = {
          approvals_reviewer = "auto_review";
          default_tools_approval_mode = "approve";
          destructive_enabled = true;
          open_world_enabled = true;
        };
      };

      dgx.userOverlays.armen.codex.active = cfg.enable && cfg.codex.enable;
      dgx.userOverlays.armen.codex.packages = lib.optionals (cfg.enable && cfg.codex.enable) [
        codexPackage
      ];
    }

    (lib.mkIf (cfg.enable && cfg.codex.enable) {
      home.packages = cfg.codex.packages;

      # The official standalone installer placed its launcher here and this
      # directory precedes the Nix profile on the pilot PATH. Own the same
      # launcher declaratively so the Nix package cannot be shadowed. The old
      # standalone release tree remains untouched as a rollback input.
      home.file.".local/bin/codex" = {
        source = "${codexPackage}/bin/codex";
        force = true;
      };
    })

    (lib.mkIf (cfg.enable && cfg.codex.relaxedPermissions.enable) {
      home.activation.dgxArmenCodexRelaxedDefaults = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [[ -v DRY_RUN ]]; then
          echo "Would reconcile Armen's non-secret Codex permission defaults"
        else
          ${codexRelaxedDefaultsReconciler}/bin/dgx-reconcile-codex-relaxed-defaults \
            --apply ${lib.escapeShellArg "${config.home.homeDirectory}/.codex/config.toml"}
        fi
      '';
    })
  ];
}
