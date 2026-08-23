{
  description = "Declarative userland and fleet configuration for DGX Spark";

  inputs = {
    # Stable foundation for the fleet and Home Manager.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Narrow, independently pinned source for fast-moving selected apps. Do not
    # replace the stable package set with this input wholesale.
    nixpkgs-apps.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

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
      nixpkgs-apps,
      home-manager,
      hyprland,
      ...
    }:
    let
      system = "aarch64-linux";
      lib = nixpkgs.lib;

      # This is an evaluation exception, not a package selection. LM Studio is
      # the only currently selected package whose Nix metadata is unfree.
      approvedUnfreePackageNames = [ "lmstudio" ];

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = false;
      };

      appsPkgs = import nixpkgs-apps {
        inherit system;
        config = {
          allowUnfree = false;
          allowUnfreePredicate = package: builtins.elem (lib.getName package) approvedUnfreePackageNames;
        };
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
          profileModules ? [ ],
        }:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          extraSpecialArgs = {
            inherit
              appsPkgs
              approvedUnfreePackageNames
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
          ]
          ++ profileModules;
        };

      pilot = {
        hostName = "sparkle-01";
        userName = "n0b0dy";
      };

      sparkleHome = mkHome pilot;

      baseProfile = mkHome (
        pilot
        // {
          profileModules = [
            {
              dgx.desktop.mode = lib.mkForce "headless";
              dgx.desktop.hyprland.portal.enable = lib.mkForce false;
            }
          ];
        }
      );

      graphicalProfile = mkHome (
        pilot
        // {
          profileModules = [
            {
              dgx.desktop.mode = lib.mkForce "gnome";
              dgx.desktop.hyprland.portal.enable = lib.mkForce false;
            }
          ];
        }
      );

      hyprlandProfile = mkHome (
        pilot
        // {
          profileModules = [
            {
              dgx.desktop.mode = lib.mkForce "hyprland";
              dgx.desktop.hyprland.portal.enable = lib.mkForce false;
            }
          ];
        }
      );

      hyprlandPortalProfile = mkHome (
        pilot
        // {
          profileModules = [
            {
              dgx.desktop.mode = lib.mkForce "hyprland";
              dgx.desktop.hyprland.portal.enable = lib.mkForce true;
            }
          ];
        }
      );

      packageNames = packages: lib.sort builtins.lessThan (map lib.getName packages);

      basePackageNames = packageNames baseProfile.config.dgx.fleetBase.packages;
      graphicalBasePackageNames = packageNames graphicalProfile.config.dgx.fleetBase.packages;
      headlessSharedGraphicalPackageNames = packageNames baseProfile.config.dgx.sharedGraphical.packages;
      sharedGraphicalPackageNames = packageNames graphicalProfile.config.dgx.sharedGraphical.packages;
      graphicalPackageNames = packageNames (
        graphicalProfile.config.dgx.fleetBase.packages
        ++ graphicalProfile.config.dgx.sharedGraphical.packages
      );

      expectedBasePackageNames = [
        "devbox"
        "lazydocker"
        "ncdu"
      ];

      expectedSharedGraphicalPackageNames = [ "ghostty" ];

      expectedGraphicalPackageNames = [
        "devbox"
        "ghostty"
        "lazydocker"
        "ncdu"
      ];

      licenseName =
        license:
        if builtins.isAttrs license && license ? spdxId then
          license.spdxId
        else if builtins.isAttrs license && license ? shortName then
          license.shortName
        else if builtins.isAttrs license && license ? fullName then
          license.fullName
        else
          "unknown";

      packageLicenses =
        package:
        let
          rawLicense = package.meta.license or null;
        in
        if rawLicense == null then [ ] else map licenseName (lib.toList rawLicense);

      packageIsFree =
        package:
        let
          rawLicense = package.meta.license or null;
          licenses = if rawLicense == null then [ ] else lib.toList rawLicense;
        in
        licenses != [ ] && lib.all (license: builtins.isAttrs license && (license.free or false)) licenses;

      mkPackageRecord = source: package: {
        inherit source;
        pname = package.pname or (lib.getName package);
        version = package.version or (lib.getVersion package);
        licenses = packageLicenses package;
        free = packageIsFree package;
        drvPath = package.drvPath;
        outputPath = package.outPath;
      };

      profileRecords =
        home: map (mkPackageRecord "composed Home Manager profile") (lib.unique home.config.home.packages);

      profileManifests = {
        schemaVersion = 1;
        inherit system approvedUnfreePackageNames;

        sources = {
          nixpkgsStable = {
            branch = "nixos-26.05";
            rev = nixpkgs.rev;
          };
          nixpkgsApps = {
            branch = "nixpkgs-unstable";
            rev = nixpkgs-apps.rev;
          };
          hyprland = {
            tag = "v0.56.2";
            rev = hyprland.rev;
          };
        };

        roles = {
          fleetBase = [
            (mkPackageRecord "nixpkgs-stable" pkgs.ncdu)
            (mkPackageRecord "nixpkgs-stable" pkgs.lazydocker)
            (mkPackageRecord "nixpkgs-apps" appsPkgs.devbox)
          ];
          sharedGraphical = [ (mkPackageRecord "nixpkgs-stable" pkgs.ghostty) ];
          hyprland = [ (mkPackageRecord "hyprland input" hyprlandPackage) ];
          hyprlandPortal = [
            (mkPackageRecord "hyprland input" hyprlandPortalPackage)
            (mkPackageRecord "nixpkgs-stable" pkgs.xdg-desktop-portal-gtk)
          ];
        };

        evaluatedProfiles = {
          headless = profileRecords baseProfile;
          gnome = profileRecords graphicalProfile;
          hyprland = profileRecords hyprlandProfile;
          hyprlandWithPortal = profileRecords hyprlandPortalProfile;
        };
      };

      stableRejectsVscode = !(builtins.tryEval pkgs.vscode.outPath).success;
      appsRejectsVscode = !(builtins.tryEval appsPkgs.vscode.outPath).success;
      appsAllowsLmStudio = (builtins.tryEval appsPkgs.lmstudio.outPath).success;

      profilePolicyCheck =
        assert basePackageNames == expectedBasePackageNames;
        assert graphicalBasePackageNames == expectedBasePackageNames;
        assert headlessSharedGraphicalPackageNames == [ ];
        assert sharedGraphicalPackageNames == expectedSharedGraphicalPackageNames;
        assert graphicalPackageNames == expectedGraphicalPackageNames;
        assert !baseProfile.config.xdg.enable;
        assert !baseProfile.config.xdg.mime.enable;
        assert !baseProfile.config.xdg.mimeApps.enable;
        assert !baseProfile.config.xdg.userDirs.enable;
        assert !baseProfile.config.xdg.portal.enable;
        assert !baseProfile.config.programs.home-manager.enable;
        assert !baseProfile.config.programs.man.enable;
        assert !baseProfile.config.programs.man.man-db.enable;
        assert !baseProfile.config.manual.manpages.enable;
        assert !baseProfile.config.dgx.userOverlays.armen.graphical.active;
        assert graphicalProfile.config.xdg.enable;
        assert graphicalProfile.config.xdg.mime.enable;
        assert !graphicalProfile.config.xdg.mimeApps.enable;
        assert !graphicalProfile.config.xdg.userDirs.enable;
        assert !graphicalProfile.config.xdg.portal.enable;
        assert graphicalProfile.config.dgx.userOverlays.armen.graphical.active;
        assert !hyprlandProfile.config.xdg.portal.enable;
        assert hyprlandPortalProfile.config.xdg.portal.enable;
        assert stableRejectsVscode;
        assert appsRejectsVscode;
        assert appsAllowsLmStudio;
        pkgs.runCommand "dgx-profile-policy" { } ''
          touch "$out"
        '';

      homeConfigurations = {
        "n0b0dy@sparkle-01" = sparkleHome;
      };
    in
    {
      inherit homeConfigurations;

      packages.${system} = {
        hyprland = hyprlandPackage;
        xdg-desktop-portal-hyprland = hyprlandPortalPackage;
      };

      checks.${system} = {
        home-sparkle-01 = sparkleHome.activationPackage;
        home-base = baseProfile.activationPackage;
        home-graphical = graphicalProfile.activationPackage;
        home-hyprland = hyprlandProfile.activationPackage;
        home-hyprland-with-portal = hyprlandPortalProfile.activationPackage;
        profile-policy = profilePolicyCheck;
      };

      lib.dgxProfileManifests.${system} = profileManifests;

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
