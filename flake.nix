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

    # System Manager's private wrapper must use the same reviewed current Nix
    # release as the host, not the older pkgs.nix from stable Nixpkgs.
    nix-release.url = "github:NixOS/nix/2.35.2";

    # Root-level configuration for the existing Ubuntu/DGX OS substrate. Keep
    # this on the branch matching stable Nixpkgs and never let it own the Nix
    # installation itself.
    system-manager = {
      url = "github:numtide/system-manager/release-26.05";
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
      nix-release,
      system-manager,
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

      devboxPackage = appsPkgs.callPackage ./packages/devbox { };

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

      tailscalePackage = pkgs.callPackage ./packages/tailscale { };
      tailscaleService = pkgs.callPackage ./root/tailscale/unit.nix {
        tailscale = tailscalePackage;
      };

      verifiedNixPackage = nix-release.packages.${system}.nix;

      # Upstream System Manager 1.1.0 invokes systemd-tmpfiles globally when
      # its managed tmpfiles set is empty. That crosses the factory-substrate
      # ownership boundary, so patch only this exact manager release.
      systemManagerEnginePatch = ./patches/system-manager/skip-empty-tmpfiles.patch;
      reviewedSystemManagerEnginePatchSha256 = "32756de30fd5730ebe60cce6ef89fc924ccd4eb3530e21ceb53fdf6073ba0e9a";

      rootManagerOverlays = [
        (_final: previous: {
          nix = verifiedNixPackage;
          rustPlatform = previous.rustPlatform // {
            buildRustPackage =
              args:
              let
                package = previous.rustPlatform.buildRustPackage args;
              in
              if (args.pname or null) == "system-manager" && (args.version or null) == "1.1.0" then
                package.overrideAttrs (oldAttrs: {
                  patches = (oldAttrs.patches or [ ]) ++ [ systemManagerEnginePatch ];
                  passthru = (oldAttrs.passthru or { }) // {
                    dgxSkipEmptyTmpfilesPatch = systemManagerEnginePatch;
                  };
                })
              else
                package;
          };
        })
      ];

      rootManagerPkgs = import nixpkgs {
        inherit system;
        overlays = rootManagerOverlays;
        config.allowUnfree = false;
      };

      rootCanary = system-manager.lib.makeSystemConfig {
        overlays = rootManagerOverlays;
        modules = [ ./hosts/sparkle-01/system.nix ];
      };

      # Disposable-only second generation for registration/switching tests. It
      # inherits the exact canary policy and changes only the harmless marker
      # payload. It is not exported as a host package or activation target.
      rootCanaryRegistrationTestGeneration = system-manager.lib.makeSystemConfig {
        overlays = rootManagerOverlays;
        modules = [
          ./hosts/sparkle-01/system.nix
          {
            environment.etc."dgx-setup/canary".text = lib.mkForce ''
              schema=1
              host=sparkle-01
              owner=DGX-setup
              purpose=system-manager activation and rollback canary
              registration-test-generation=2
            '';
          }
        ];
      };

      systemManagerPackage = rootManagerPkgs.callPackage "${system-manager}/package.nix" { };
      rootCanaryConfig = rootCanary.config;
      rootCanaryRegistrationTestConfig = rootCanaryRegistrationTestGeneration.config;
      rootCanaryServiceNames = lib.sort builtins.lessThan (
        builtins.attrNames rootCanaryConfig.build.services
      );
      rootCanaryRegistrationTestServiceNames = lib.sort builtins.lessThan (
        builtins.attrNames rootCanaryRegistrationTestConfig.build.services
      );
      rootCanaryEtcNames = lib.sort builtins.lessThan (
        builtins.attrNames rootCanaryConfig.build.etc.entries
      );
      rootCanaryRegistrationTestEtcNames = lib.sort builtins.lessThan (
        builtins.attrNames rootCanaryRegistrationTestConfig.build.etc.entries
      );
      rootCanaryPackageNames = packageNames rootCanaryConfig.environment.systemPackages;
      rootCanaryRegistrationTestPackageNames = packageNames rootCanaryRegistrationTestConfig.environment.systemPackages;
      rootCanaryClosureInfo = pkgs.closureInfo {
        rootPaths = [ rootCanary ];
      };
      rootCanaryPilotGcRoot = "/nix/var/nix/gcroots/dgx-setup-root-canary-pilot";

      expectedRootCanaryServiceNames = [
        "dgx-setup-canary.service"
        "sysinit-reactivation.target"
        "system-manager.target"
      ];

      expectedRootCanaryEtcNames = [
        "dgx-setup/canary"
        "systemd/system"
      ];

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
              devboxPackage
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

      selectedPersonalGraphicalCandidates = [
        appsPkgs.chromium
        appsPkgs.lmstudio
        appsPkgs.zed-editor
      ];

      expectedPersonalGraphicalCandidateNames = [
        "chromium"
        "lmstudio"
        "zed-editor"
      ];

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
            (mkPackageRecord "official Devbox release override on nixpkgs-apps" devboxPackage)
          ];
          sharedGraphical = [ (mkPackageRecord "nixpkgs-stable" pkgs.ghostty) ];
          personalGraphicalCandidates = map (mkPackageRecord "nixpkgs-apps; selected but not installed") selectedPersonalGraphicalCandidates;
          hyprland = [ (mkPackageRecord "hyprland input" hyprlandPackage) ];
          hyprlandPortal = [
            (mkPackageRecord "hyprland input" hyprlandPortalPackage)
            (mkPackageRecord "nixpkgs-stable" pkgs.xdg-desktop-portal-gtk)
          ];
          fleetAccess = [
            (mkPackageRecord "official Tailscale stable ARM64 artifact" tailscalePackage)
          ];
          repositoryDevShell = [
            (mkPackageRecord "nixpkgs-apps" appsPkgs.git)
            (mkPackageRecord "nixpkgs-stable" pkgs.jq)
            (mkPackageRecord "nixpkgs-stable" pkgs.nixfmt-tree)
            (mkPackageRecord "nixpkgs-apps" appsPkgs.ripgrep)
          ];
        };

        services.tailscale = {
          availableUnits = [
            "tailscaled.service"
            "tailscale-wait-online.service"
            "tailscale-online.target"
          ];
          packageOutputPath = tailscalePackage.outPath;
          unitOutputPath = tailscaleService.package.outPath;
          wantedBy = [ "multi-user.target" ];
          statePath = "/var/lib/tailscale/tailscaled.state";
          socketPath = "/run/tailscale/tailscaled.sock";
          # Declarative side-effect flag: this output is inert. It is not a
          # live-host observation of the apt-owned daemon.
          activated = false;
        };

        evaluatedProfiles = {
          headless = profileRecords baseProfile;
          gnome = profileRecords graphicalProfile;
          hyprland = profileRecords hyprlandProfile;
          hyprlandWithPortal = profileRecords hyprlandPortalProfile;
        };
      };

      rootManagerManifest = {
        schemaVersion = 1;
        inherit system;
        hostName = "sparkle-01";

        manager = {
          name = "system-manager";
          version = systemManagerPackage.version;
          licenses = packageLicenses systemManagerPackage;
          branch = "release-26.05";
          rev = system-manager.rev;
          lastModified = system-manager.lastModified;
          drvPath = systemManagerPackage.drvPath;
          rootOutputPath = rootCanary.outPath;
          # Declarative side-effect flag: evaluating/building this output does
          # not activate it. Current live state is recorded under
          # root/system-manager/validation/.
          activated = false;
          patches = [
            {
              name = "skip-empty-tmpfiles";
              path = "patches/system-manager/skip-empty-tmpfiles.patch";
              sha256 = builtins.hashFile "sha256" systemManagerEnginePatch;
              reason = "Prevent global systemd-tmpfiles execution when no managed tmpfiles configuration exists.";
            }
          ];
        };

        privateNixRuntime = {
          version = verifiedNixPackage.version;
          rev = nix-release.rev;
          outputPath = verifiedNixPackage.outPath;
          ownsHostInstallation = false;
        };

        policy = {
          ownsNix = false;
          ownsUsers = false;
          enablesSetuidWrappers = false;
          exportsGlobalPath = false;
          linksCurrentSystem = false;
          startsAtBoot = false;
          globalPackages = rootCanaryPackageNames;
          etcEntries = rootCanaryEtcNames;
          services = rootCanaryServiceNames;
          replaceExisting = false;
          ports = [ ];
          mutableState = [ "/var/lib/system-manager/state/system-manager-state.json" ];
          managedTmpfiles = [ ];
          invokesGlobalTmpfiles = false;
          tmpfilesMode = "skip-when-empty";
        };

        managerState = {
          path = "/var/lib/system-manager/state/system-manager-state.json";
          createdByLowLevelActivation = true;
          removedByDeactivation = false;
        };

        registration = {
          # The repository evaluation performs no registration. This is not a
          # probe of mutable host paths.
          performed = false;
          profile = "/nix/var/nix/profiles/system-manager-profiles/system-manager";
          gcRoot = "/nix/var/nix/gcroots/system-manager-current";

          isolatedLifecycleTest =
            let
              observedDrvPath = "/nix/store/m4zm42h6f8dch5mfm6aq6cpjp9jwzk90-container-test-dgx-root-canary-registration.drv";
              observedOutputPath = "/nix/store/jkl1lsqnvmv5iznk7q70xjk9l6xfvf6j-container-test-dgx-root-canary-registration";
            in
            {
              verifiedAt = "2026-09-01T12:54:16Z";
              result = "passed";
              inherit observedDrvPath observedOutputPath;
              baselineOutputPath = rootCanary.outPath;
              secondGenerationOutputPath = rootCanaryRegistrationTestGeneration.outPath;
              currentDrvPath = rootCanaryRegistrationContainerTest.drvPath;
              currentOutputPath = rootCanaryRegistrationContainerTest.outPath;
              matchesCurrent =
                rootCanaryRegistrationContainerTest.drvPath == observedDrvPath
                && rootCanaryRegistrationContainerTest.outPath == observedOutputPath;
              evidence = "root/system-manager/validation/2026-09-01-registration-container-test.md";
              hostRegistrationPerformed = false;
              hostActivationPerformed = false;
              hostPostflight = "clean";
            };
        };

        pilotRetention = {
          path = rootCanaryPilotGcRoot;
          # The repository evaluation does not create this root. The retained
          # host canary currently has it; see the live validation record.
          created = false;
          requiredForLowLevelActivation = true;
          removeOnlyAfterDeactivation = true;
          replacesRegistration = false;
        };

        isolatedTest =
          let
            observedDrvPath = "/nix/store/jcrdk9p9lz3qiya2l1021339lsdvyxcg-container-test-dgx-root-canary.drv";
            observedOutputPath = "/nix/store/wn9dffp852vnvri1vcvz4mskmdgilnn0-container-test-dgx-root-canary";
          in
          {
            performedAt = "2026-08-23T21:11:00Z";
            result = "passed";
            inherit observedDrvPath observedOutputPath;
            currentDrvPath = rootCanaryContainerTest.drvPath;
            evidence = "root/system-manager/validation/2026-08-24-container-test.md";
            currentOutputPath = rootCanaryContainerTest.outPath;
            matchesCurrent =
              rootCanaryContainerTest.drvPath == observedDrvPath
              && rootCanaryContainerTest.outPath == observedOutputPath;
            hostActivationPerformed = false;
            hostPostflight = "clean";
          };

        canary = {
          etcPath = "/etc/dgx-setup/canary";
          service = "dgx-setup-canary.service";
          target = "system-manager.target";
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
        assert packageNames selectedPersonalGraphicalCandidates == expectedPersonalGraphicalCandidateNames;
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

      tailscalePolicyCheck =
        assert tailscalePackage.version == tailscalePackage.passthru.release.version;
        assert tailscalePackage.passthru.release.architecture == "arm64";
        assert tailscalePackage.passthru.release.track == "stable";
        assert
          tailscalePackage.passthru.release.url
          == "https://pkgs.tailscale.com/stable/tailscale_${tailscalePackage.version}_arm64.tgz";
        assert lib.hasInfix "/var/lib/tailscale/tailscaled.state" tailscaleService.unitText;
        assert lib.hasInfix "/run/tailscale/tailscaled.sock" tailscaleService.unitText;
        assert lib.hasInfix "WantedBy=multi-user.target" tailscaleService.unitText;
        assert lib.hasInfix "/bin/tailscale wait" tailscaleService.waitOnlineUnitText;
        assert lib.hasInfix "Requires=tailscale-wait-online.service" tailscaleService.onlineTargetText;
        pkgs.runCommand "dgx-tailscale-policy" { } ''
          touch "$out"
        '';

      devboxPolicyCheck =
        assert devboxPackage.version == devboxPackage.passthru.release.version;
        assert devboxPackage.passthru.release.tag == devboxPackage.version;
        assert devboxPackage.passthru.release.owner == "jetify-com";
        assert devboxPackage.passthru.release.repo == "devbox";
        pkgs.runCommand "dgx-devbox-policy" { } ''
          touch "$out"
        '';

      rootManagerPolicyCheck =
        assert systemManagerPackage.version == "1.1.0";
        assert systemManagerPackage.dgxSkipEmptyTmpfilesPatch == systemManagerEnginePatch;
        assert
          builtins.hashFile "sha256" systemManagerEnginePatch == reviewedSystemManagerEnginePatchSha256;
        assert verifiedNixPackage.version == "2.35.2";
        assert rootCanaryConfig.nixpkgs.hostPlatform == system;
        assert rootCanaryServiceNames == expectedRootCanaryServiceNames;
        assert rootCanaryEtcNames == expectedRootCanaryEtcNames;
        assert rootCanaryPackageNames == [ ];
        assert rootCanaryRegistrationTestServiceNames == expectedRootCanaryServiceNames;
        assert rootCanaryRegistrationTestEtcNames == expectedRootCanaryEtcNames;
        assert rootCanaryRegistrationTestPackageNames == [ ];
        assert rootCanaryRegistrationTestGeneration.outPath != rootCanary.outPath;
        assert !rootCanaryConfig.nix.enable;
        assert !rootCanaryRegistrationTestConfig.nix.enable;
        assert !rootCanaryRegistrationTestConfig.services.userborn.enable;
        assert !rootCanaryRegistrationTestConfig.security.enableWrappers;
        assert !rootCanaryRegistrationTestConfig.system-manager.linkCurrentSystem;
        assert rootCanaryRegistrationTestConfig.systemd.targets.system-manager.wantedBy == [ ];
        assert rootManagerManifest.registration.isolatedLifecycleTest.result == "passed";
        assert rootManagerManifest.registration.isolatedLifecycleTest.matchesCurrent;
        assert rootManagerManifest.registration.isolatedLifecycleTest.hostPostflight == "clean";
        assert !rootManagerManifest.registration.isolatedLifecycleTest.hostRegistrationPerformed;
        assert !rootManagerManifest.registration.isolatedLifecycleTest.hostActivationPerformed;
        assert !rootCanaryConfig.services.userborn.enable;
        assert !rootCanaryConfig.security.enableWrappers;
        assert !rootCanaryConfig.system-manager.linkCurrentSystem;
        assert rootCanaryConfig.systemd.targets.system-manager.wantedBy == [ ];
        assert !rootCanaryConfig.environment.etc."dgx-setup/canary".replaceExisting;
        assert !rootCanaryConfig.environment.etc."tmpfiles.d".enable;
        assert rootCanaryConfig.systemd.tmpfiles.rules == [ ];
        assert rootCanaryConfig.systemd.tmpfiles.settings == { };
        pkgs.runCommand "dgx-root-manager-policy" { } ''
          if grep -Eq -- '-nix-2\.34\.8$' ${rootCanaryClosureInfo}/store-paths; then
            echo "The root-manager closure retained stale Nix 2.34.8." >&2
            exit 1
          fi
          if grep -Eq -- '-userborn-[0-9]' ${rootCanaryClosureInfo}/store-paths; then
            echo "The inert root-manager closure retained userborn." >&2
            exit 1
          fi
          grep -Fx -- '${systemManagerPackage}' ${rootCanaryClosureInfo}/store-paths \
            >/dev/null
          grep -Fx -- '${verifiedNixPackage}' ${rootCanaryClosureInfo}/store-paths \
            >/dev/null
          touch "$out"
        '';

      rootCanaryContainerTest = system-manager.lib.containerTest.makeContainerTest {
        hostPkgs = pkgs;
        name = "dgx-root-canary";
        toplevel = rootCanary;
        testScript = ''
          import json

          start_all()
          machine.wait_for_unit("multi-user.target")

          state_path = "/var/lib/system-manager/state/system-manager-state.json"
          profile_path = "/nix/var/nix/profiles/system-manager-profiles/system-manager"
          gcroot_path = "/nix/var/nix/gcroots/system-manager-current"
          unmanaged_tmpfiles_sentinel = "/run/dgx-unmanaged-tmpfiles-sentinel"

          protected_paths = [
              "/etc/nix/nix.conf",
              "/etc/passwd",
              "/etc/group",
              "/etc/shadow",
          ]

          def protected_snapshot() -> dict[str, str]:
              return {
                  path: machine.succeed(
                      f"if test -e '{path}'; then sha256sum '{path}' | cut -d' ' -f1; else printf absent; fi"
                  ).strip()
                  for path in protected_paths
              }

          def assert_absent(path: str) -> None:
              machine.fail(f"test -e '{path}' || test -L '{path}'")

          machine.succeed(
              "echo 'f /run/dgx-unmanaged-tmpfiles-sentinel 0644 root root - blocked' "
              "> /etc/tmpfiles.d/dgx-unmanaged.conf"
          )
          before = protected_snapshot()

          with subtest("Canary is inert before activation"):
              assert_absent(unmanaged_tmpfiles_sentinel)
              assert_absent("/etc/dgx-setup/canary")
              assert_absent("/etc/profile.d/system-manager-path.sh")
              assert_absent("/etc/environment.d/10-system-manager.conf")
              assert_absent("/run/current-system")
              assert_absent("/etc/systemd/system/default.target.wants/system-manager.target")
              machine.fail(f"test -e {state_path}")
              assert_absent(profile_path)
              assert_absent(gcroot_path)

          activation_logs = machine.activate()
          assert "ERROR" not in activation_logs, activation_logs
          machine.wait_for_unit("system-manager.target")
          machine.wait_for_unit("dgx-setup-canary.service")

          with subtest("Activation owns only the bounded canary"):
              assert_absent(unmanaged_tmpfiles_sentinel)
              machine.succeed("test -L /etc/dgx-setup/canary")
              machine.succeed("grep -Fx 'host=sparkle-01' /etc/dgx-setup/canary")
              assert_absent("/etc/profile.d/system-manager-path.sh")
              assert_absent("/etc/environment.d/10-system-manager.conf")
              assert_absent("/run/current-system")
              assert_absent("/etc/systemd/system/default.target.wants/system-manager.target")
              assert_absent("/etc/systemd/system/userborn.service")
              assert_absent("/etc/systemd/system/run-wrappers.mount")
              assert_absent("/etc/systemd/system/suid-sgid-wrappers.service")
              activated_state = json.loads(machine.succeed(f"cat {state_path}"))
              assert activated_state["version"] == 1
              assert set(activated_state["fileTree"]["files"]) == {
                  "/etc/dgx-setup/canary",
                  "/etc/systemd/system/dgx-setup-canary.service",
                  "/etc/systemd/system/sysinit-reactivation.target",
                  "/etc/systemd/system/system-manager.target",
                  "/etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service",
              }
              assert set(activated_state["services"].keys()) == {
                  "dgx-setup-canary.service",
                  "sysinit-reactivation.target",
                  "system-manager.target",
              }
              assert_absent(profile_path)
              assert_absent(gcroot_path)
              assert protected_snapshot() == before

          machine.succeed("${rootCanary}/bin/deactivate")

          with subtest("Deactivation removes ownership and leaves empty bookkeeping"):
              for path in [
                  "/etc/dgx-setup/canary",
                  "/etc/systemd/system/dgx-setup-canary.service",
                  "/etc/systemd/system/sysinit-reactivation.target",
                  "/etc/systemd/system/system-manager.target",
                  "/etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service",
              ]:
                  assert_absent(path)
              assert_absent(unmanaged_tmpfiles_sentinel)
              deactivated_state = json.loads(machine.succeed(f"cat {state_path}"))
              assert deactivated_state == {
                  "fileTree": {"files": [], "backedUpFiles": []},
                  "services": {},
                  "version": 0,
              }
              assert_absent(profile_path)
              assert_absent(gcroot_path)
              assert protected_snapshot() == before
        '';
      };

      rootCanaryRegistrationContainerTest = system-manager.lib.containerTest.makeContainerTest {
        hostPkgs = pkgs;
        name = "dgx-root-canary-registration";
        toplevel = rootCanary;
        extraPathsToRegister = [ rootCanaryRegistrationTestGeneration ];
        testScript = ''
          import json

          start_all()
          machine.wait_for_unit("multi-user.target")

          generation_one = "${rootCanary}"
          generation_two = "${rootCanaryRegistrationTestGeneration}"
          nix_env = "${verifiedNixPackage}/bin/nix-env"
          state_path = "/var/lib/system-manager/state/system-manager-state.json"
          profile_dir = "/nix/var/nix/profiles/system-manager-profiles"
          profile_path = f"{profile_dir}/system-manager"
          gcroot_path = "/nix/var/nix/gcroots/system-manager-current"
          unmanaged_tmpfiles_sentinel = "/run/dgx-unmanaged-tmpfiles-sentinel"

          managed_paths = [
              "/etc/dgx-setup/canary",
              "/etc/systemd/system/dgx-setup-canary.service",
              "/etc/systemd/system/sysinit-reactivation.target",
              "/etc/systemd/system/system-manager.target",
              "/etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service",
          ]
          forbidden_paths = [
              "/etc/profile.d/system-manager-path.sh",
              "/etc/environment.d/10-system-manager.conf",
              "/etc/systemd/system/default.target.wants/system-manager.target",
              "/etc/systemd/system/system-manager-path.service",
              "/etc/systemd/system/userborn.service",
              "/run/current-system",
              "/run/wrappers",
          ]
          protected_paths = [
              "/etc/nix/nix.conf",
              "/etc/passwd",
              "/etc/group",
              "/etc/shadow",
          ]

          def protected_snapshot() -> dict[str, str]:
              return {
                  path: machine.succeed(
                      f"if test -e '{path}'; then sha256sum '{path}' | cut -d' ' -f1; else printf absent; fi"
                  ).strip()
                  for path in protected_paths
              }

          def assert_absent(path: str) -> None:
              machine.fail(f"test -e '{path}' || test -L '{path}'")

          def resolved(path: str) -> str:
              return machine.succeed(f"readlink -f -- '{path}'").strip()

          def generation_links() -> list[str]:
              output = machine.succeed(
                  f"find '{profile_dir}' -maxdepth 1 -type l "
                  "-name 'system-manager-*-link' -printf '%f\\n' | sort -V"
              )
              return [line for line in output.splitlines() if line]

          def assert_registration(target: str) -> None:
              machine.succeed(f"test -L '{profile_path}'")
              machine.succeed(f"test -L '{gcroot_path}'")
              assert resolved(profile_path) == target
              assert resolved(gcroot_path) == target

          def assert_bounded_state() -> None:
              state = json.loads(machine.succeed(f"cat '{state_path}'"))
              assert state["version"] == 1
              assert set(state["fileTree"]["files"]) == set(managed_paths)
              assert state["fileTree"]["backedUpFiles"] == []
              assert set(state["services"].keys()) == {
                  "dgx-setup-canary.service",
                  "sysinit-reactivation.target",
                  "system-manager.target",
              }

          machine.succeed(
              "echo 'f /run/dgx-unmanaged-tmpfiles-sentinel 0644 root root - blocked' "
              "> /etc/tmpfiles.d/dgx-unmanaged.conf"
          )
          before = protected_snapshot()

          with subtest("Registration failure is detectably non-transactional"):
              machine.succeed(f"printf blocked > '{gcroot_path}'")
              machine.fail(f"'{generation_one}/bin/register-profile'")
              machine.succeed(f"test -f '{gcroot_path}'")
              machine.fail(f"test -L '{gcroot_path}'")
              machine.succeed(f"test -L '{profile_path}'")
              assert resolved(profile_path) == generation_one
              links = generation_links()
              assert links == ["system-manager-1-link"], links
              assert resolved(f"{profile_dir}/{links[0]}") == generation_one
              for path in managed_paths:
                  assert_absent(path)
              machine.fail(f"test -e '{state_path}'")
              assert_absent(unmanaged_tmpfiles_sentinel)
              assert protected_snapshot() == before

          with subtest("Reset only the disposable partial-registration fixture"):
              machine.succeed(f"unlink '{profile_path}'")
              machine.succeed(
                  f"for link in '{profile_dir}'/system-manager-*-link; do "
                  "test ! -L \"$link\" || unlink \"$link\"; done"
              )
              machine.succeed(f"unlink '{gcroot_path}'")
              assert_absent(profile_path)
              assert_absent(gcroot_path)
              assert generation_links() == []

          with subtest("Register generation one without activating it"):
              machine.succeed(f"'{generation_one}/bin/register-profile'")
              assert_registration(generation_one)
              links = generation_links()
              assert links == ["system-manager-1-link"], links
              assert resolved(f"{profile_dir}/{links[0]}") == generation_one
              for path in managed_paths:
                  assert_absent(path)
              machine.fail(f"test -e '{state_path}'")
              assert_absent(unmanaged_tmpfiles_sentinel)
              assert protected_snapshot() == before

          with subtest("Explicitly activate registered generation one"):
              activation_logs = machine.succeed(f"'{profile_path}/bin/activate'")
              assert "ERROR" not in activation_logs, activation_logs
              machine.wait_for_unit("system-manager.target")
              machine.wait_for_unit("dgx-setup-canary.service")
              machine.succeed("grep -Fx 'host=sparkle-01' /etc/dgx-setup/canary")
              machine.fail(
                  "grep -Fx 'registration-test-generation=2' "
                  "/etc/dgx-setup/canary"
              )
              assert_bounded_state()
              assert_registration(generation_one)
              for path in forbidden_paths:
                  assert_absent(path)
              assert_absent(unmanaged_tmpfiles_sentinel)
              assert protected_snapshot() == before

          with subtest("Register generation two without switching live state"):
              machine.succeed(f"'{generation_two}/bin/register-profile'")
              assert_registration(generation_two)
              links = generation_links()
              assert links == [
                  "system-manager-1-link",
                  "system-manager-2-link",
              ], links
              assert resolved(f"{profile_dir}/system-manager-1-link") == generation_one
              assert resolved(f"{profile_dir}/system-manager-2-link") == generation_two
              machine.fail(
                  "grep -Fx 'registration-test-generation=2' "
                  "/etc/dgx-setup/canary"
              )
              assert_bounded_state()
              assert_absent(unmanaged_tmpfiles_sentinel)
              assert protected_snapshot() == before

          with subtest("Explicitly activate registered generation two"):
              activation_logs = machine.succeed(f"'{profile_path}/bin/activate'")
              assert "ERROR" not in activation_logs, activation_logs
              machine.wait_for_unit("system-manager.target")
              machine.wait_for_unit("dgx-setup-canary.service")
              machine.succeed(
                  "grep -Fx 'registration-test-generation=2' "
                  "/etc/dgx-setup/canary"
              )
              assert_bounded_state()
              assert_registration(generation_two)
              for path in forbidden_paths:
                  assert_absent(path)
              assert_absent(unmanaged_tmpfiles_sentinel)
              assert protected_snapshot() == before

          with subtest("Selecting the prior profile neither activates nor refreshes the extra root"):
              machine.succeed(
                  f"'{nix_env}' --profile '{profile_path}' --switch-generation 1"
              )
              assert resolved(profile_path) == generation_one
              assert resolved(gcroot_path) == generation_two
              machine.succeed(
                  "grep -Fx 'registration-test-generation=2' "
                  "/etc/dgx-setup/canary"
              )
              assert_bounded_state()
              assert_absent(unmanaged_tmpfiles_sentinel)
              assert protected_snapshot() == before

          with subtest("Re-register and explicitly activate the selected rollback generation"):
              machine.succeed(f"'{generation_one}/bin/register-profile'")
              assert_registration(generation_one)
              activation_logs = machine.succeed(f"'{profile_path}/bin/activate'")
              assert "ERROR" not in activation_logs, activation_logs
              machine.wait_for_unit("system-manager.target")
              machine.wait_for_unit("dgx-setup-canary.service")
              machine.succeed("grep -Fx 'host=sparkle-01' /etc/dgx-setup/canary")
              machine.fail(
                  "grep -Fx 'registration-test-generation=2' "
                  "/etc/dgx-setup/canary"
              )
              assert_bounded_state()
              for path in forbidden_paths:
                  assert_absent(path)
              assert_absent(unmanaged_tmpfiles_sentinel)
              assert protected_snapshot() == before

          with subtest("Deactivation removes ownership but retains registration history"):
              machine.succeed(f"'{profile_path}/bin/deactivate'")
              for path in managed_paths:
                  assert_absent(path)
              deactivated_state = json.loads(machine.succeed(f"cat '{state_path}'"))
              assert deactivated_state == {
                  "fileTree": {"files": [], "backedUpFiles": []},
                  "services": {},
                  "version": 0,
              }
              assert_registration(generation_one)
              links = generation_links()
              assert "system-manager-1-link" in links
              assert "system-manager-2-link" in links
              for path in forbidden_paths:
                  assert_absent(path)
              assert_absent(unmanaged_tmpfiles_sentinel)
              assert protected_snapshot() == before
        '';
      };

      homeConfigurations = {
        "n0b0dy@sparkle-01" = sparkleHome;
      };
    in
    {
      inherit homeConfigurations;

      systemConfigs.sparkle-01 = rootCanary;

      packages.${system} = {
        devbox = devboxPackage;
        hyprland = hyprlandPackage;
        root-system-canary = rootCanary;
        tailscale = tailscalePackage;
        tailscaled-unit = tailscaleService.package;
        xdg-desktop-portal-hyprland = hyprlandPortalPackage;
      };

      checks.${system} = {
        devbox-package = devboxPackage;
        devbox-policy = devboxPolicyCheck;
        home-sparkle-01 = sparkleHome.activationPackage;
        home-base = baseProfile.activationPackage;
        home-graphical = graphicalProfile.activationPackage;
        home-hyprland = hyprlandProfile.activationPackage;
        home-hyprland-with-portal = hyprlandPortalProfile.activationPackage;
        profile-policy = profilePolicyCheck;
        root-canary-container = rootCanaryContainerTest;
        root-canary-registration-container = rootCanaryRegistrationContainerTest;
        root-manager-policy = rootManagerPolicyCheck;
        root-system-canary = rootCanary;
        tailscale-package = tailscalePackage;
        tailscale-policy = tailscalePolicyCheck;
        tailscaled-unit = tailscaleService.package;
      };

      lib.dgxProfileManifests.${system} = profileManifests;
      lib.dgxRootManagerManifest.${system} = rootManagerManifest;

      devShells.${system}.default = pkgs.mkShellNoCC {
        packages = [
          appsPkgs.git
          pkgs.jq
          pkgs.nixfmt-tree
          appsPkgs.ripgrep
        ];
      };

      formatter.${system} = pkgs.nixfmt-tree;
    };
}
