{
  pkgs,
  lib,
  home-manager,
  devboxPackage,
}:
let
  gpustackControl = import ../workloads/gpustack { inherit pkgs; };
  hosts = (builtins.fromJSON (builtins.readFile ./hosts.json)).hosts;
  makeHome =
    host:
    home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit devboxPackage; };
      modules = [
        ../modules/home/base.nix
        {
          home.username = host.user;
          home.homeDirectory = host.homeDirectory;
          home.stateVersion = "26.05";
          # Only the package output is activated by dgx-workstation. Existing
          # APT packages, dotfiles, desktop, and the normal Nix profile are separate.
          systemd.user.enable = false;
          xdg.enable = false;
          xdg.mime.enable = false;
          xdg.portal.enable = false;
          home.packages =
            (map (
              name: lib.attrByPath (lib.splitString "." name) (throw "Unknown workstation package: ${name}") pkgs
            ) host.packages)
            ++ [
              gpustackControl
              (pkgs.writeShellScriptBin "spark" ''
                exec ${pkgs.python3}/bin/python3 ${lib.escapeShellArg "${host.homeDirectory}/Development/DGX-setup/scripts/dgx-workstation"} "$@"
              '')
              (pkgs.writeShellScriptBin "vllm_stop" ''
                export SPARK_GPUSTACK_CONTROL=${gpustackControl}/bin/gpustack-spark
                exec ${pkgs.python3}/bin/python3 ${../scripts/vllm_stop} "$@"
              '')
            ];
        }
      ];
    };
  homes = lib.mapAttrs (_: makeHome) hosts;
in
{
  homeConfigurations = lib.mapAttrs' (
    name: host: lib.nameValuePair "${host.user}@${name}" homes.${name}
  ) hosts;
  packages = lib.mapAttrs' (
    name: host:
    lib.nameValuePair "workstation-${name}" (
      pkgs.runCommand "sparkwerx-${host.user}"
        {
          passthru.homeConfiguration = homes.${name};
        }
        ''
          mkdir -p "$out"
          ln -s ${homes.${name}.config.home.path}/bin "$out/bin"
          cp ${
            pkgs.writeText "workstation.json" (
              builtins.toJSON {
                schemaVersion = 1;
                hostName = name;
                inherit (host)
                  user
                  uid
                  homeDirectory
                  system
                  ;
                commands = [
                  "ncdu"
                  "lazydocker"
                  "devbox"
                  "spark"
                  "vllm_stop"
                  "gpustack-spark"
                ];
                packages = map (p: {
                  name = lib.getName p;
                  version = lib.getVersion p;
                }) homes.${name}.config.home.packages;
              }
            )
          } "$out/workstation.json"
        ''
    )
  ) hosts;
}
