{
  config,
  lib,
  ...
}:

let
  cfg = config.dgx.root.tailscale;
in
{
  options.dgx.root.tailscale = {
    enable = lib.mkEnableOption "the repository-owned Tailscale access-plane service";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        Exact reviewed Tailscale package. The default is deliberately empty so
        the minimal root canary cannot acquire Tailscale by implication.
      '';
    };

    sshDesired = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Desired Tailscale SSH state. This module records and asserts the
        choice; the mutable preference remains in Tailscale state and is
        verified by the migration transaction rather than written to the Nix
        store.
      '';
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion =
            cfg.enable
            || !(builtins.hasAttr "tailscaled" config.systemd.services)
            || !config.systemd.services.tailscaled.enable;
          message = "tailscaled.service requires the explicit DGX Tailscale role.";
        }
      ];
    }

    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.package != null;
          message = "The DGX Tailscale role requires an exact reviewed package.";
        }
        {
          assertion = cfg.sshDesired;
          message = "The current fleet access role requires Tailscale SSH desired state.";
        }
      ];

      systemd.services.tailscaled = {
        description = "Tailscale node agent (DGX fleet access plane)";
        wants = [ "network-pre.target" ];
        after = [
          "network-pre.target"
          "NetworkManager.service"
          "systemd-resolved.service"
        ];
        wantedBy = [ "multi-user.target" ];
        environment = {
          PORT = "41641";
          FLAGS = "";
        };
        serviceConfig = {
          Type = "notify";
          EnvironmentFile = "-/etc/dgx-setup/tailscaled.env";
          ExecStart = "${cfg.package}/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock --port=\${PORT} $FLAGS";
          ExecStopPost = "${cfg.package}/bin/tailscaled --cleanup";
          Restart = "on-failure";
          RuntimeDirectory = "tailscale";
          RuntimeDirectoryMode = "0755";
          StateDirectory = "tailscale";
          StateDirectoryMode = "0700";
          CacheDirectory = "tailscale";
          CacheDirectoryMode = "0750";
        };
      };
    })
  ];
}
