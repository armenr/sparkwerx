{
  description = "Declarative userland and fleet configuration for DGX Spark";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hyprland moves faster than stable Nixpkgs. Pin the latest reviewed
    # upstream release independently so the rest of the fleet remains stable.
    hyprland.url = "github:hyprwm/Hyprland/v0.56.2";
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      hyprland,
      ...
    }:
    let
      system = "aarch64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      # Hyprland v0.56.2 ships glaze 8 but its CMake constraint rejects it.
      # This mirrors upstream fix 91f29f2 without moving the source off the tag.
      hyprlandPackage = hyprland.packages.${system}.hyprland.overrideAttrs (oldAttrs: {
        postPatch = (oldAttrs.postPatch or "") + ''
          substituteInPlace CMakeLists.txt \
            --replace-fail "find_package(glaze 7...<8 QUIET)" \
            "find_package(glaze QUIET)"
        '';
      });

      hyprlandPortalPackage = hyprland.packages.${system}.xdg-desktop-portal-hyprland.override {
        hyprland = hyprlandPackage;
      };

      mkHome =
        {
          hostName,
          userName,
          homeDirectory ? "/home/${userName}",
        }:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          extraSpecialArgs = {
            inherit
              hostName
              userName
              hyprlandPackage
              hyprlandPortalPackage
              ;
          };

          modules = [
            ./hosts/${hostName}/home.nix
            {
              home = {
                username = userName;
                inherit homeDirectory;
                stateVersion = "26.05";
              };
            }
          ];
        };

      homeConfigurations = {
        "n0b0dy@sparkle-01" = mkHome {
          hostName = "sparkle-01";
          userName = "n0b0dy";
        };
      };
    in
    {
      inherit homeConfigurations;

      packages.${system} = {
        hyprland = hyprlandPackage;
        xdg-desktop-portal-hyprland = hyprlandPortalPackage;
      };

      checks.${system}.home-sparkle-01 = homeConfigurations."n0b0dy@sparkle-01".activationPackage;

      devShells.${system}.default = pkgs.mkShellNoCC {
        packages = with pkgs; [
          git
          jq
          nixfmt-tree
          ripgrep
        ];
      };

      formatter.${system} = pkgs.nixfmt-tree;
    };
}
