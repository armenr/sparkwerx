{
  description = "Declarative userland and fleet configuration for DGX Spark";

  inputs = {
    # Stable foundation for the fleet and Home Manager.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Immutable foundation for the currently live System Manager closure and
    # its exact disposable-test evidence. User/package refreshes must not move
    # this input; advance it only through a separately reviewed root generation.
    nixpkgs-root.url = "github:NixOS/nixpkgs/a9e6d84f9c2f9012f5fe7d964a7851352300e61a";

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
      inputs.nixpkgs.follows = "nixpkgs-root";
    };

    # Hyprland moves faster than stable Nixpkgs. Pin the latest reviewed
    # upstream release independently so the rest of the fleet remains stable.
    hyprland.url = "github:hyprwm/Hyprland/v0.56.2";
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-root,
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
      rootLib = nixpkgs-root.lib;
      fleetSpec = builtins.fromJSON (builtins.readFile ./fleet/hosts.json);
      fleetHosts = fleetSpec.hosts;
      nixBootstrapSpec = builtins.fromJSON (builtins.readFile ./bootstrap/nix/source.json);
      nixRuntimeStorePaths = import ./root/nix/store-paths.nix;

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
      codexPackage = pkgs.callPackage ./packages/codex-cli { };
      chromiumPackage = appsPkgs.chromium;
      chromiumSandboxPackage = chromiumPackage.sandbox;
      lmstudioPackage = appsPkgs.callPackage ./packages/lmstudio { };
      zedPackage = pkgs.callPackage ./packages/zed-editor { };

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

      rootPkgs = import nixpkgs-root {
        inherit system;
        overlays = rootManagerOverlays;
        config.allowUnfree = false;
      };

      rootCanary = system-manager.lib.makeSystemConfig {
        overlays = rootManagerOverlays;
        modules = [ ./hosts/sparkle-01/system.nix ];
      };

      # Reviewed, harmless second-generation canary candidate. It inherits the
      # exact generation-one policy and changes only the marker payload. The
      # package export makes its store output evaluable and buildable; nothing
      # here retains, registers, activates, or links it at boot on the host.
      rootCanaryRegistrationTestGeneration = system-manager.lib.makeSystemConfig {
        overlays = rootManagerOverlays;
        modules = [
          ./hosts/sparkle-01/system.nix
          {
            environment.etc."dgx-setup/canary".text = rootLib.mkForce ''
              schema=1
              host=sparkle-01
              owner=DGX-setup
              purpose=system-manager activation and rollback canary
              registration-test-generation=2
            '';
          }
        ];
      };

      # Reviewed boot-persistence candidate. It inherits generation two and
      # adds exactly one declarative boot edge plus a harmless identity marker.
      # Evaluating or building this output does not retain, register, activate,
      # boot-link, or reboot anything on the host.
      rootCanaryBootPersistenceGeneration = system-manager.lib.makeSystemConfig {
        overlays = rootManagerOverlays;
        modules = [
          ./hosts/sparkle-01/system.nix
          {
            dgx.root.bootPersistence.enable = true;
            environment.etc."dgx-setup/canary".text = rootLib.mkForce ''
              schema=1
              host=sparkle-01
              owner=DGX-setup
              purpose=system-manager activation and rollback canary
              registration-test-generation=2
              boot-persistence-generation=3
            '';
          }
        ];
      };

      # First access-plane ownership candidate. It inherits the exact retained
      # generation-three canary and boot edge, then adds only the pinned
      # Tailscale service. Building this output does not register, activate,
      # restart, enroll, or remove the apt rollback package on the host.
      rootTailscaleMigrationGeneration = system-manager.lib.makeSystemConfig {
        overlays = rootManagerOverlays;
        modules = [
          ./hosts/sparkle-01/system.nix
          {
            dgx.root = {
              bootPersistence.enable = true;
              tailscale = {
                enable = true;
                package = tailscalePackage;
                sshDesired = true;
              };
            };
            environment.etc."dgx-setup/canary".text = rootLib.mkForce ''
              schema=1
              host=sparkle-01
              owner=DGX-setup
              purpose=system-manager activation and rollback canary
              registration-test-generation=2
              boot-persistence-generation=3
              tailscale-migration-generation=4
            '';
          }
        ];
      };

      # First host desktop-controller candidates. Both preserve exact
      # generation-four Tailscale ownership and the boot edge. Their only new
      # root surface is the pair of thin DGX mode targets, the selected
      # default.target dispatcher, and a non-secret mode marker. Building either
      # candidate does not switch a target, stop GDM, or change the live host.
      mkRootDesktopModeGeneration =
        mode:
        system-manager.lib.makeSystemConfig {
          overlays = rootManagerOverlays;
          modules = [
            ./hosts/sparkle-01/system.nix
            {
              dgx.root = {
                bootPersistence.enable = true;
                tailscale = {
                  enable = true;
                  package = tailscalePackage;
                  sshDesired = true;
                };
                desktop = {
                  enable = true;
                  inherit mode;
                };
              };
              environment.etc."dgx-setup/canary".text = rootLib.mkForce ''
                schema=1
                host=sparkle-01
                owner=DGX-setup
                purpose=system-manager activation and rollback canary
                registration-test-generation=2
                boot-persistence-generation=3
                tailscale-migration-generation=4
                desktop-controller-generation=5
                desktop-mode=${mode}
              '';
            }
          ];
        };

      rootDesktopHeadlessGeneration = mkRootDesktopModeGeneration "headless";
      rootDesktopGnomeGeneration = mkRootDesktopModeGeneration "gnome";

      systemManagerPackage = rootPkgs.callPackage "${system-manager}/package.nix" { };
      rootCanaryConfig = rootCanary.config;
      rootCanaryRegistrationTestConfig = rootCanaryRegistrationTestGeneration.config;
      rootCanaryBootPersistenceConfig = rootCanaryBootPersistenceGeneration.config;
      rootTailscaleMigrationConfig = rootTailscaleMigrationGeneration.config;
      rootDesktopHeadlessConfig = rootDesktopHeadlessGeneration.config;
      rootDesktopGnomeConfig = rootDesktopGnomeGeneration.config;
      rootCanaryServiceNames = lib.sort builtins.lessThan (
        builtins.attrNames rootCanaryConfig.build.services
      );
      rootCanaryRegistrationTestServiceNames = lib.sort builtins.lessThan (
        builtins.attrNames rootCanaryRegistrationTestConfig.build.services
      );
      rootCanaryBootPersistenceServiceNames = lib.sort builtins.lessThan (
        builtins.attrNames rootCanaryBootPersistenceConfig.build.services
      );
      rootTailscaleMigrationServiceNames = lib.sort builtins.lessThan (
        builtins.attrNames rootTailscaleMigrationConfig.build.services
      );
      rootDesktopHeadlessServiceNames = lib.sort builtins.lessThan (
        builtins.attrNames rootDesktopHeadlessConfig.build.services
      );
      rootDesktopGnomeServiceNames = lib.sort builtins.lessThan (
        builtins.attrNames rootDesktopGnomeConfig.build.services
      );
      rootCanaryEtcNames = lib.sort builtins.lessThan (
        builtins.attrNames rootCanaryConfig.build.etc.entries
      );
      rootCanaryRegistrationTestEtcNames = lib.sort builtins.lessThan (
        builtins.attrNames rootCanaryRegistrationTestConfig.build.etc.entries
      );
      rootCanaryBootPersistenceEtcNames = lib.sort builtins.lessThan (
        builtins.attrNames rootCanaryBootPersistenceConfig.build.etc.entries
      );
      rootTailscaleMigrationEtcNames = lib.sort builtins.lessThan (
        builtins.attrNames rootTailscaleMigrationConfig.build.etc.entries
      );
      rootDesktopHeadlessEtcNames = lib.sort builtins.lessThan (
        builtins.attrNames rootDesktopHeadlessConfig.build.etc.entries
      );
      rootDesktopGnomeEtcNames = lib.sort builtins.lessThan (
        builtins.attrNames rootDesktopGnomeConfig.build.etc.entries
      );
      rootCanaryPackageNames = packageNames rootCanaryConfig.environment.systemPackages;
      rootCanaryRegistrationTestPackageNames = packageNames rootCanaryRegistrationTestConfig.environment.systemPackages;
      rootCanaryBootPersistencePackageNames = packageNames rootCanaryBootPersistenceConfig.environment.systemPackages;
      rootTailscaleMigrationPackageNames = packageNames rootTailscaleMigrationConfig.environment.systemPackages;
      rootDesktopHeadlessPackageNames = packageNames rootDesktopHeadlessConfig.environment.systemPackages;
      rootDesktopGnomePackageNames = packageNames rootDesktopGnomeConfig.environment.systemPackages;
      rootCanaryClosureInfo = rootPkgs.closureInfo {
        rootPaths = [ rootCanary ];
      };
      rootCanaryPilotGcRoot = "/nix/var/nix/gcroots/dgx-setup-root-canary-pilot";
      rootRegistrationTransactionProgram = ./scripts/root-registration-transaction.sh;
      reviewedRootRegistrationTransactionSha256 = "86c4be22ed350782920905897d80616b3949998d2662fd04ab9d1f5c3f4078a9";
      rootGenerationSwitchTransactionProgram = ./scripts/root-generation-switch-transaction.sh;
      reviewedRootGenerationSwitchTransactionSha256 = "ea1a6ddc509eef4ac80aa165e29a6612d1f1b59b93681cdf813ee8b1ff6d8cdd";
      rootBootPersistenceTransactionProgram = ./scripts/root-boot-persistence-transaction.sh;
      reviewedRootBootPersistenceTransactionSha256 = "53eb8c4d03a4c24764f519e358f3c5c813e66f189efc07e50f82cd19841d8288";
      rootBootPersistenceSnapshotProgram = ./scripts/snapshot-root-boot-persistence.sh;
      reviewedRootBootPersistenceSnapshotSha256 = "bb726566b5e11ed466aaab0ab7ab12e3f40f7f93af4561767bfbdb500f4640ff";
      rootBootPersistencePilotProgram = ./scripts/activate-root-boot-persistence-pilot.sh;
      reviewedRootBootPersistencePilotSha256 = "464f2b8283fbed336722ae96ee3786d3188b1cfba09f588974dd9381b8a58e70";
      rootCanaryAuditProgram = ./scripts/audit-root-canary-state.sh;
      reviewedRootCanaryAuditSha256 = "19cac3ba416dc3705c9dc1a996afb82840e8f4bc2d657a78f969f3f42cfddb12";
      rootRebootRecoveryTransactionProgram = ./scripts/root-reboot-recovery-transaction.sh;
      reviewedRootRebootRecoveryTransactionSha256 = "b1f04f39169cc000b5a532545439693bafd9d6c62d0190e9aac2c231394a6be9";
      rootRebootRecoverySnapshotProgram = ./scripts/snapshot-root-reboot-recovery.sh;
      reviewedRootRebootRecoverySnapshotSha256 = "89a2ec821eb58169510c208965e546ad8311521f6534bc090d7d9799b8ebf0c4";
      rootRebootRecoveryPilotProgram = ./scripts/root-reboot-recovery-pilot.sh;
      rootTailscaleMigrationTransactionProgram = ./scripts/root-tailscale-migration-transaction.sh;
      rootDesktopModeTransactionProgram = ./scripts/root-desktop-mode-transaction.sh;
      reviewedRootDesktopModeTransactionSha256 = "6b62ba0ee094d664ffa059c43cf1da87f39b2790ed0d93708ad9ec0432a60fe4";
      rootDesktopSwitchOperatorProgram = ./scripts/dgx-desktop;
      reviewedRootDesktopSwitchOperatorSha256 = "5e55964f27c855af1001e7ec692db6a72408ff0f37763887fbc89b9cc0eed902";
      rootDesktopSwitchBundle = import ./root/desktop/switch-bundle.nix {
        pkgs = rootPkgs;
        transactionProgram = rootDesktopModeTransactionProgram;
        generationOne = rootCanary;
        generationTwo = rootCanaryRegistrationTestGeneration;
        generationThree = rootCanaryBootPersistenceGeneration;
        generationFour = rootTailscaleMigrationGeneration;
        headlessGeneration = rootDesktopHeadlessGeneration;
      };
      rootTailscaleMigrationBundle = import ./root/tailscale/migration-bundle.nix {
        pkgs = rootPkgs;
        transactionProgram = rootTailscaleMigrationTransactionProgram;
        generationOne = rootCanary;
        generationTwo = rootCanaryRegistrationTestGeneration;
        generationThree = rootCanaryBootPersistenceGeneration;
        generationFour = rootTailscaleMigrationGeneration;
      };
      reviewedRootRebootRecoveryPilotSha256 = "09770fd391efae16c205ef06e5bcba8bbc9de970103af79b53164aab395e8f4a";
      rootRebootRecoveryOperatorProgram = ./scripts/dgx-recovery;
      reviewedRootRebootRecoveryOperatorSha256 = "a7da45053e625f1653f6bc0d4830073ddc272cd03b80bce9db53badee37dd885";
      rootRecoveryRestoreGenerationThreeProgram = ./scripts/root-recovery-restore-generation-three.sh;
      reviewedRootRecoveryRestoreGenerationThreeSha256 = "ebf64626d6cf316d789de20f48edb2ac75fa3b2bed8b3c5bbdcf37fa1288af58";
      codexRelaxedDefaultsReconcilerProgram = ./scripts/reconcile-codex-relaxed-defaults.sh;
      codexRelaxedDefaultsTestProgram = ./scripts/test-reconcile-codex-relaxed-defaults.sh;
      rootRebootRecoveryGcRoot = "/nix/var/nix/gcroots/dgx-setup-root-canary-reboot-recovery-pilot";
      mkRootRebootRecoveryBundle =
        {
          name,
          onBootSec,
        }:
        rootPkgs.runCommand name
          {
            nativeBuildInputs = [ rootPkgs.makeWrapper ];
          }
          ''
            mkdir -p "$out/bin" "$out/lib/systemd/system"

            makeWrapper ${rootPkgs.bash}/bin/bash "$out/bin/dgx-root-reboot-recovery" \
              --add-flags '${rootRebootRecoveryTransactionProgram}' \
              --set DGX_RECOVERY_BUNDLE "$out" \
              --set DGX_RECOVERY_GENERATION_ONE '${rootCanary}' \
              --set DGX_RECOVERY_GENERATION_TWO '${rootCanaryRegistrationTestGeneration}' \
              --set DGX_RECOVERY_GENERATION_THREE '${rootCanaryBootPersistenceGeneration}' \
              --set DGX_RECOVERY_BOOT_TRANSACTION '${rootBootPersistenceTransactionProgram}' \
              --set DGX_RECOVERY_AUDIT '${rootCanaryAuditProgram}' \
              --set DGX_RECOVERY_PATH '${
                rootLib.makeBinPath [
                  rootPkgs.coreutils
                  rootPkgs.findutils
                  rootPkgs.gnugrep
                  rootPkgs.jq
                  rootPkgs.util-linux
                ]
              }:/nix/var/nix/profiles/default/bin:/usr/sbin:/usr/bin:/sbin:/bin'

            cat >"$out/lib/systemd/system/dgx-root-reboot-recovery.service" <<EOF
            [Unit]
            Description=DGX System Manager first-reboot automatic rollback
            After=local-fs.target
            RequiresMountsFor=/nix /var/lib/system-manager
            ConditionPathExists=/var/lib/dgx-setup/reboot-recovery/state

            [Service]
            Type=oneshot
            ExecStart=$out/bin/dgx-root-reboot-recovery rollback
            TimeoutStartSec=5min
            StandardOutput=journal+console
            StandardError=journal+console
            EOF

            cat >"$out/lib/systemd/system/dgx-root-reboot-recovery.timer" <<EOF
            [Unit]
            Description=DGX System Manager first-reboot rollback deadline
            ConditionPathExists=/var/lib/dgx-setup/reboot-recovery/state

            [Timer]
            OnBootSec=${onBootSec}
            AccuracySec=1s
            RandomizedDelaySec=0
            Unit=dgx-root-reboot-recovery.service
            RemainAfterElapse=no

            [Install]
            WantedBy=timers.target
            EOF

            chmod 0444 "$out/lib/systemd/system/"*.service \
              "$out/lib/systemd/system/"*.timer
          '';
      rootRebootRecoveryBundle = mkRootRebootRecoveryBundle {
        name = "dgx-root-reboot-recovery";
        onBootSec = "10min";
      };
      rootRebootRecoveryTestBundle = mkRootRebootRecoveryBundle {
        name = "dgx-root-reboot-recovery-test";
        onBootSec = "30s";
      };
      rootGenerationSwitchSnapshotProgram = ./scripts/snapshot-root-generation-switch.sh;
      reviewedRootGenerationSwitchSnapshotSha256 = "a82669f4a7001d370d0b0bb26815d466600114137b2fa26da1bc1169ae30a9ec";
      rootGenerationSwitchPilotProgram = ./scripts/switch-root-canary-generation-pilot.sh;
      reviewedRootGenerationSwitchPilotSha256 = "e9432ea70cc8d8705e7775b4aaddd92e5bf1d1e56c8f11d1cb537abb2c2d143c";
      systemdSnapshotPropertyProgram = ./scripts/systemd-snapshot-property.sh;
      reviewedSystemdSnapshotPropertySha256 = "1123fe7efa54c21aaa9b1609ba132bdbe3a66a50deff41da33e826eb37d332af";
      systemdSnapshotPropertyTestProgram = ./scripts/test-systemd-snapshot-property.sh;
      reviewedSystemdSnapshotPropertyTestSha256 = "d9829ce6200752e0bb93810b2cc59cc5f137483abf4dc5a5f9ea491826585009";

      expectedRootCanaryServiceNames = [
        "dgx-setup-canary.service"
        "sysinit-reactivation.target"
        "system-manager.target"
      ];

      expectedRootTailscaleMigrationServiceNames = expectedRootCanaryServiceNames ++ [
        "tailscaled.service"
      ];

      expectedRootDesktopServiceNames = expectedRootTailscaleMigrationServiceNames;

      expectedRootCanaryEtcNames = [
        "dgx-setup/canary"
        "systemd/system"
      ];

      expectedRootDesktopEtcNames = [
        "dgx-setup/canary"
        "dgx-setup/desktop-mode"
        "systemd/system"
      ];

      mkHome =
        {
          hostName,
          userName,
          homeDirectory ? "/home/${userName}",
          hostSpec ? fleetHosts.${hostName},
          profileModules ? [ ],
        }:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          extraSpecialArgs = {
            inherit
              appsPkgs
              approvedUnfreePackageNames
              codexPackage
              devboxPackage
              hostName
              hostSpec
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

      sparkleHost = fleetHosts.sparkle-01;
      sparkleArmen = sparkleHost.users.armen;

      pilot = {
        hostName = "sparkle-01";
        userName = sparkleArmen.unixName;
        homeDirectory = sparkleArmen.homeDirectory;
        hostSpec = sparkleHost;
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

      # Disposable second-generation fixture for the user-profile rollback
      # test. It preserves the exact headless package/file/service boundary and
      # changes only an inert session-variable payload so the activation output
      # is guaranteed to differ from the live candidate.
      homeUpdateRollbackTestProfile = mkHome (
        pilot
        // {
          profileModules = [
            {
              dgx.desktop.mode = lib.mkForce "headless";
              dgx.desktop.hyprland.portal.enable = lib.mkForce false;
              home.sessionVariables.DGX_HOME_UPDATE_ROLLBACK_TEST = "1";
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

      expectedArmenAllModesPackageNames = [ "codex-cli" ];

      selectedPersonalGraphicalCandidates = [
        chromiumPackage
        lmstudioPackage
        zedPackage
      ];

      expectedPersonalGraphicalCandidateNames = [
        "chromium"
        "lmstudio"
        "zed-editor"
      ];

      personalGraphicalCandidatesAbsentFrom =
        profile:
        lib.intersectLists expectedPersonalGraphicalCandidateNames (
          packageNames profile.config.home.packages
        ) == [ ];

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
          armenAllModes = [
            (mkPackageRecord "official OpenAI stable ARM64 release bundle" codexPackage)
          ];
          personalGraphicalCandidates = [
            (mkPackageRecord "nixpkgs-apps; built but not installed" chromiumPackage)
            (mkPackageRecord "official LM Studio stable ARM64 AppImage; built but not installed" lmstudioPackage)
            (mkPackageRecord "official Zed stable ARM64 bundle; built but not installed" zedPackage)
          ];
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
          # Declarative side-effect flag: evaluating this output is inert.
          # The separately recorded deployment below is the live-host fact.
          activated = false;
          rootCandidate = rootTailscaleMigrationGeneration.outPath;
          ownershipState = "nix-managed";
        };

        policies.armenCodexRelaxedDefaults = {
          enabled = sparkleHome.config.dgx.userOverlays.armen.codex.relaxedPermissions.active;
          scope = "Armen only; every desktop mode";
          settings = sparkleHome.config.dgx.userOverlays.armen.codex.relaxedPermissions.policy;
          preservesUnrelatedMutableConfig = true;
          ownsCodexPackage = true;
          package = mkPackageRecord "official OpenAI stable ARM64 release bundle" codexPackage;
          launcher = "~/.local/bin/codex is Home Manager-owned in every desktop mode";
        };

        policies.chromiumSandbox = {
          package = mkPackageRecord "nixpkgs-apps; built but not installed" chromiumPackage;
          sandboxOutputPath = chromiumSandboxPackage.outPath;
          preferredRuntimePath = "/run/wrappers/bin/__chromium-suid-sandbox";
          storeHelperIsSetuid = false;
          hostIntegrationDeclared = false;
          noSandboxFallbackAccepted = false;
        };

        deployments.sparkle01Home = {
          hostName = "sparkle-01";
          userName = "n0b0dy";
          mode = "headless";
          status = "active-generation-one-retained";
          snapshotCreatedAt = "2026-09-03T12:05:19Z";
          retainedSnapshot = "20260903T120519Z";
          realRollbackSnapshot = "20260903T120400Z";
          observedCandidate = "/nix/store/naw1cln02ark00v6wxss5flijlh3nr57-home-manager-generation";
          currentCandidate = baseProfile.activationPackage.outPath;
          matchesCurrent =
            baseProfile.activationPackage.outPath
            == "/nix/store/naw1cln02ark00v6wxss5flijlh3nr57-home-manager-generation";
          observedUserEnvironment = "/nix/store/6cdhd5n7m5agcrnr8pg6jxkpsadmfpba-user-environment";
          observedHomeFiles = "/nix/store/cshkglrpyf9gzih2iyaccq0gwl87gcya-home-manager-files";
          userSystemdEnabled = false;
          rollbackArmed = false;
          realRollbackPassed = true;
          evidence = "docs/2026-09-03-home-headless-host.md";
        };

        deployments.sparkle01Tailscale = {
          hostName = "sparkle-01";
          status = "nix-managed-confirmed-after-reboot";
          confirmedOn = "2026-09-05";
          deployedFromRepositoryCommit = "f57e51d142db30edfe44fd4d6694d22a822a6d24";
          snapshot = "inventory/sparkle-01/raw/tailscale-migration/20260905T084503Z";
          observedCandidate = "/nix/store/vjw778sf95r42a1zbivlk8z4p45y7qhx-system-manager";
          currentCandidate = rootTailscaleMigrationGeneration.outPath;
          matchesCurrent =
            rootTailscaleMigrationGeneration.outPath
            == "/nix/store/vjw778sf95r42a1zbivlk8z4p45y7qhx-system-manager";
          profileGeneration = 4;
          mutableIdentityPreserved = true;
          tailscaleSshReconnectVerified = true;
          rebootVerified = true;
          rollbackArmed = false;
          aptFallbackRetained = true;
          evidence = "root/tailscale/validation/2026-09-05-host-attempt-2.md";
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

        foundationNixpkgs = {
          policy = "frozen-live-root-lane";
          sourceBranch = "nixos-26.05";
          rev = nixpkgs-root.rev;
          lastModified = nixpkgs-root.lastModified;
          advancesWithUserPackages = false;
        };

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

          guardedFirstGeneration = {
            status = "completed-first-generation-registration-retained";
            transactionProgram = {
              repositoryPath = "scripts/root-registration-transaction.sh";
              sha256 = builtins.hashFile "sha256" rootRegistrationTransactionProgram;
            };
            profileDirectory = "/nix/var/nix/profiles/system-manager-profiles";
            generationOne = "/nix/var/nix/profiles/system-manager-profiles/system-manager-1-link";
            exactCandidate = rootCanary.outPath;
            requiresActiveUnregisteredCanary = true;
            preservesLiveActivation = true;
            preservesPilotRetention = true;
            createsBootLink = false;
            restartsServices = false;
            liveRegistrationPerformed = true;
            liveRegistration = {
              stateClass = "ACTIVE_REGISTERED_RETAINED";
              host = "sparkle-01";
              registeredAt = "2026-09-01T20:19:13Z";
              repositoryCommit = "0f03d01d46e9fbd340676d8c91d4f2697bd25ce4";
              snapshot = "inventory/sparkle-01/raw/system-manager-registration/20260901T201613Z";
              evidence = "root/system-manager/validation/2026-09-01-first-registration-host-attempt-3.md";
              localConsoleConfirmed = true;
              rollbackDisarmed = true;
            };
            rollback = {
              timerUnit = "dgx-root-registration-rollback.timer";
              delayMinutes = 10;
              restoresProfileState = "absent";
              restoresExtraGcRootState = "absent";
              leavesLiveActivation = "exact retained canary";
              leavesPilotRetention = "exact candidate";
            };
            isolatedTransactionTest =
              let
                observedDrvPath = "/nix/store/lxnykcyvjn18pdv7y9rr1ryhvjgicazg-container-test-dgx-root-canary-registration-transaction.drv";
                observedOutputPath = "/nix/store/mrslm372127pgwbfv3r7kprj2igxpki2-container-test-dgx-root-canary-registration-transaction";
              in
              {
                verifiedAt = "2026-09-01T15:04:47Z";
                result = "passed";
                inherit observedDrvPath observedOutputPath;
                outputHash = "sha256:1smdvp76zf0hz5cxzjjghf8c2z4hjkvbkwf4ikmgpf2cz8fv4ram";
                currentDrvPath = rootCanaryRegistrationTransactionContainerTest.drvPath;
                currentOutputPath = rootCanaryRegistrationTransactionContainerTest.outPath;
                matchesCurrent =
                  rootCanaryRegistrationTransactionContainerTest.drvPath == observedDrvPath
                  && rootCanaryRegistrationTransactionContainerTest.outPath == observedOutputPath;
                hostRegistrationPerformed = false;
                hostActivationPerformed = false;
                hostPostflight = "clean";
                evidence = "root/system-manager/validation/2026-09-01-first-registration-transaction-container-test.md";
              };
          };

          guardedGenerationSwitch = {
            status = "live-generation-two-registered-retained";
            transactionProgram = {
              repositoryPath = "scripts/root-generation-switch-transaction.sh";
              sha256 = builtins.hashFile "sha256" rootGenerationSwitchTransactionProgram;
            };
            exactCandidates = {
              generationOne = rootCanary.outPath;
              generationTwo = rootCanaryRegistrationTestGeneration.outPath;
            };
            profileDirectory = "/nix/var/nix/profiles/system-manager-profiles";
            selectedProfile = "/nix/var/nix/profiles/system-manager-profiles/system-manager";
            generationOneLink = "/nix/var/nix/profiles/system-manager-profiles/system-manager-1-link";
            generationTwoLink = "/nix/var/nix/profiles/system-manager-profiles/system-manager-2-link";
            upstreamGcRoot = "/nix/var/nix/gcroots/system-manager-current";
            retention = {
              generationOne = rootCanaryPilotGcRoot;
              generationTwo = "/nix/var/nix/gcroots/dgx-setup-root-canary-generation-two-pilot";
            };
            requiredHostState = "ACTIVE_REGISTERED_RETAINED";
            currentHostState = "ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED";
            initialHostState = "generation one selected, extra-rooted, and live; generation two absent";
            preState = "generation one selected, extra-rooted, and live; generation two retained only";
            postState = "generation two selected, extra-rooted, and live; generation one retained";
            rollbackState = "exact registered and active generation one";
            preservesGenerationOne = true;
            preservesBothPilotRoots = true;
            createsBootLink = false;
            changesServiceOwnership = false;
            hostGenerationTwoRetentionPerformed = true;
            liveSwitchPerformed = true;
            evidencePlan = "root/system-manager/validation/2026-09-02-generation-switch-transaction-plan.md";
            livePilot = {
              status = "generation-two-retained-after-console-confirmation";
              snapshotProgram = {
                repositoryPath = "scripts/snapshot-root-generation-switch.sh";
                sha256 = builtins.hashFile "sha256" rootGenerationSwitchSnapshotProgram;
              };
              switchProgram = {
                repositoryPath = "scripts/switch-root-canary-generation-pilot.sh";
                sha256 = builtins.hashFile "sha256" rootGenerationSwitchPilotProgram;
              };
              systemdSnapshotPropertyProgram = {
                repositoryPath = "scripts/systemd-snapshot-property.sh";
                sha256 = builtins.hashFile "sha256" systemdSnapshotPropertyProgram;
              };
              systemdSnapshotPropertyTest = {
                repositoryPath = "scripts/test-systemd-snapshot-property.sh";
                sha256 = builtins.hashFile "sha256" systemdSnapshotPropertyTestProgram;
                check = systemdSnapshotPropertyRegressionCheck.drvPath;
              };
              snapshot = {
                root = "inventory/sparkle-01/raw/system-manager-generation-switch";
                maximumAgeSeconds = 1800;
                owner = "root";
                mode = "0700";
                exactPreStateRequired = true;
              };
              rollback = {
                timerUnit = "dgx-root-generation-switch-rollback.timer";
                delayMinutes = 10;
                transactionAction = "rollback-switch";
                armedBeforeSwitch = true;
                restoresState = "exact registered and active generation one";
                preservesBothPilotRoots = true;
              };
              confirmation = {
                phrase = "KEEP GENERATION TWO";
                timeoutSeconds = 300;
                requiresLocalConsoleVerification = true;
                repeatedPostflightBeforeDisarm = true;
              };
              createsBootLink = false;
              changesServiceOwnership = false;
              hostGenerationTwoRetentionPerformed = true;
              liveSwitchPerformed = true;
              evidencePlan = "root/system-manager/validation/2026-09-02-generation-switch-live-plan.md";
            };
            liveSwitch = {
              stateClass = "ACTIVE_REGISTERED_GENERATION_TWO_RETAINED";
              host = "sparkle-01";
              switchedAt = "2026-09-02T08:38:17Z";
              repositoryCommit = "df6f53c7403c468722cdd709c7c9b1d568612592";
              snapshot = "inventory/sparkle-01/raw/system-manager-generation-switch/20260902T083437Z";
              evidence = "root/system-manager/validation/2026-09-02-generation-switch-host-attempt-1.md";
              localConsoleConfirmed = true;
              rollbackDisarmed = true;
              rollbackServiceRan = false;
              bootLinkCreated = false;
            };
            isolatedTransactionTest =
              let
                observedDrvPath = "/nix/store/0llhzgyraq4gr7m4agbv8wbvs7xdcql2-container-test-dgx-root-canary-generation-switch-transaction.drv";
                observedOutputPath = "/nix/store/l5s5m3q4bd338jflq1abycajwxrfbj5v-container-test-dgx-root-canary-generation-switch-transaction";
              in
              {
                verifiedAt = "2026-09-02T07:02:25Z";
                result = "passed";
                inherit observedDrvPath observedOutputPath;
                outputHash = "sha256:01zxs9x67jgp5ifskcvkr8lihddw886ysqcqgaaw3v6dr9f18766";
                currentDrvPath = rootCanaryGenerationSwitchTransactionContainerTest.drvPath;
                currentOutputPath = rootCanaryGenerationSwitchTransactionContainerTest.outPath;
                matchesCurrent =
                  rootCanaryGenerationSwitchTransactionContainerTest.drvPath == observedDrvPath
                  && rootCanaryGenerationSwitchTransactionContainerTest.outPath == observedOutputPath;
                hostRegistrationPerformed = false;
                hostActivationPerformed = false;
                hostCandidateRetentionPerformed = false;
                hostPostflight = "clean";
                evidencePlan = "root/system-manager/validation/2026-09-02-generation-switch-transaction-plan.md";
                evidence = "root/system-manager/validation/2026-09-02-generation-switch-transaction-container-test.md";
              };
          };
        };

        bootPersistence = {
          status = "live-generation-three-boot-linked-retained";
          requiredHostState = "ACTIVE_REGISTERED_GENERATION_TWO_RETAINED";
          currentHostState = "ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED";
          exactCandidates = {
            generationOne = rootCanary.outPath;
            generationTwo = rootCanaryRegistrationTestGeneration.outPath;
            generationThree = rootCanaryBootPersistenceGeneration.outPath;
          };
          delta = {
            canaryMarker = "boot-persistence-generation=3";
            managedBootLink = "/etc/systemd/system/default.target.wants/system-manager.target";
            managedBootLinkTarget = "../system-manager.target";
            serviceInventoryUnchanged = true;
            globalPackagesUnchanged = true;
            linksCurrentSystem = false;
          };
          transactionProgram = {
            repositoryPath = "scripts/root-boot-persistence-transaction.sh";
            sha256 = builtins.hashFile "sha256" rootBootPersistenceTransactionProgram;
            applyAction = "apply-boot";
            rollbackAction = "rollback-boot";
            rollbackState = "exact registered and active no-boot generation two";
          };
          retention = {
            path = "/nix/var/nix/gcroots/dgx-setup-root-canary-boot-persistence-pilot";
            hostCreated = true;
            requiredBeforeTransaction = true;
            preservedByRollback = true;
          };
          isolatedTransactionTest = {
            verifiedAt = "2026-09-02T10:11:07Z";
            result = "passed";
            observedDrvPath = "/nix/store/i5skjqyw16qgbvb4azr68msrqfz64d7k-container-test-dgx-root-canary-boot-persistence-transaction.drv";
            observedOutputPath = "/nix/store/d3ymf91l07rvai5pzz9ygj3vl3g9xss3-container-test-dgx-root-canary-boot-persistence-transaction";
            outputHash = "sha256:0lxm3pjsd4yy9zl49zx6cbydc9iid1i7mdrajkinkfzszg5k7ikn";
            currentDrvPath = rootCanaryBootPersistenceTransactionContainerTest.drvPath;
            currentOutputPath = rootCanaryBootPersistenceTransactionContainerTest.outPath;
            matchesCurrent =
              rootCanaryBootPersistenceTransactionContainerTest.drvPath
              == "/nix/store/i5skjqyw16qgbvb4azr68msrqfz64d7k-container-test-dgx-root-canary-boot-persistence-transaction.drv"
              &&
                rootCanaryBootPersistenceTransactionContainerTest.outPath
                == "/nix/store/d3ymf91l07rvai5pzz9ygj3vl3g9xss3-container-test-dgx-root-canary-boot-persistence-transaction";
            failureInjectionStages = [
              "upstream-gcroot-collision"
              "after-registration"
              "after-activation"
            ];
            disposableRestarts = 2;
            provesBootStart = true;
            provesRollbackNoBoot = true;
            hostRegistrationPerformed = false;
            hostActivationPerformed = false;
            hostCandidateRetentionPerformed = false;
            hostBootLinkCreated = false;
            hostRebootPerformed = false;
            hostPostflight = "clean";
            evidencePlan = "root/system-manager/validation/2026-09-02-boot-persistence-transaction-plan.md";
            evidence = "root/system-manager/validation/2026-09-02-boot-persistence-transaction-container-test.md";
          };
          rebootRecovery =
            let
              observedDrvPath = "/nix/store/jqmx45mxqqz34d4yjh3186xadb2ai6qx-container-test-dgx-root-canary-reboot-recovery-transaction.drv";
              observedOutputPath = "/nix/store/p0ywhqdf58h5r83z1pah7arba4rqr0ka-container-test-dgx-root-canary-reboot-recovery-transaction";
            in
            {
              status = "live-recovery-operational-host-not-armed";
              requiredHostState = "ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED";
              transactionProgram = {
                repositoryPath = "scripts/root-reboot-recovery-transaction.sh";
                sha256 = builtins.hashFile "sha256" rootRebootRecoveryTransactionProgram;
              };
              postbootAuditor = {
                repositoryPath = "scripts/audit-root-canary-state.sh";
                sha256 = builtins.hashFile "sha256" rootCanaryAuditProgram;
                stateClass = "ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_REBOOTED_RETAINED";
                requiresManagerAndCanaryActive = true;
                requiresReactivationTargetInactive = true;
              };
              productionBundle = {
                outputPath = rootRebootRecoveryBundle.outPath;
                drvPath = rootRebootRecoveryBundle.drvPath;
                timerUnit = "dgx-root-reboot-recovery.timer";
                serviceUnit = "dgx-root-reboot-recovery.service";
                delayMinutes = 10;
                statePath = "/var/lib/dgx-setup/reboot-recovery/state";
                gcRoot = rootRebootRecoveryGcRoot;
              };
              confirmation = {
                phrase = "KEEP REBOOTED GENERATION THREE";
                removesRecoverySurface = true;
              };
              rollback = {
                action = "rollback";
                restoresState = "exact registered and active no-boot generation two";
                cleanupPhrase = "CLEAN ROLLED BACK REBOOT RECOVERY";
                retainsEvidenceUntilVerifiedCleanup = true;
              };
              isolatedTransactionTest = {
                verifiedAt = "2026-09-02T20:13:44Z";
                result = "passed";
                inherit observedDrvPath observedOutputPath;
                outputHash = "sha256:0v7i51bmpjghm8v3cly7i82j3ysvk3in17s5av2465wy3zhzmgp8";
                outputSriHash = "sha256-6L764R+eF0PEVkWfYOOYW/shBYrHUzY2qvDJW1co8Ww=";
                currentDrvPath = rootCanaryRebootRecoveryTransactionContainerTest.drvPath;
                currentOutputPath = rootCanaryRebootRecoveryTransactionContainerTest.outPath;
                matchesCurrent =
                  rootCanaryRebootRecoveryTransactionContainerTest.drvPath == observedDrvPath
                  && rootCanaryRebootRecoveryTransactionContainerTest.outPath == observedOutputPath;
                priorDisposableAttempts = 3;
                failureInjectionStages = [
                  "after-root"
                  "after-state"
                  "after-units"
                ];
                subtestCount = 13;
                disposableRestarts = 2;
                provesAutomaticRollback = true;
                provesConfirmedRetention = true;
                provesExactCleanup = true;
                provesSameBootDisarm = true;
                hostRecoveryArmed = false;
                hostRegistrationPerformed = false;
                hostActivationPerformed = false;
                hostBootLinkChanged = false;
                hostRebootPerformed = false;
                hostPostflight = "clean";
                evidencePlan = "root/system-manager/validation/2026-09-02-reboot-recovery-transaction-plan.md";
                evidence = "root/system-manager/validation/2026-09-02-reboot-recovery-transaction-container-test.md";
              };
              livePilot = {
                status = "repository-design-complete-host-not-armed";
                snapshotProgram = {
                  repositoryPath = "scripts/snapshot-root-reboot-recovery.sh";
                  sha256 = builtins.hashFile "sha256" rootRebootRecoverySnapshotProgram;
                };
                pilotProgram = {
                  repositoryPath = "scripts/root-reboot-recovery-pilot.sh";
                  sha256 = builtins.hashFile "sha256" rootRebootRecoveryPilotProgram;
                  actions = [
                    "arm"
                    "disarm-preboot"
                    "status"
                    "confirm"
                    "verify-rolled-back"
                    "cleanup-rolled-back"
                  ];
                  performsReboot = false;
                };
                operatorProgram = {
                  repositoryPath = "scripts/dgx-recovery";
                  sha256 = builtins.hashFile "sha256" rootRebootRecoveryOperatorProgram;
                  actions = [
                    "snapshot"
                    "restore"
                    "arm"
                    "disarm-preboot"
                    "status"
                    "confirm"
                    "verify-rolled-back"
                    "cleanup-rolled-back"
                  ];
                  invokesExactSnapshotCopyPostboot = true;
                  performsReboot = false;
                };
                nixDaemonPostbootPolicy = {
                  activeServiceAccepted = true;
                  idleServiceWithActiveSocketAccepted = true;
                  socket = "nix-daemon.socket";
                  preservesStrictSameBootProcessContinuity = true;
                };
                systemdSnapshotPropertyProgram = {
                  repositoryPath = "scripts/systemd-snapshot-property.sh";
                  sha256 = builtins.hashFile "sha256" systemdSnapshotPropertyProgram;
                };
                systemdSnapshotPropertyTest = {
                  repositoryPath = "scripts/test-systemd-snapshot-property.sh";
                  sha256 = builtins.hashFile "sha256" systemdSnapshotPropertyTestProgram;
                };
                armingConfirmation = "ARM PERSISTENT RECOVERY";
                prebootDisarmConfirmation = "DISARM PREBOOT RECOVERY";
                postbootConfirmation = "KEEP REBOOTED GENERATION THREE";
                rolledBackCleanupConfirmation = "CLEAN ROLLED BACK REBOOT RECOVERY";
                snapshotMaximumAgeSeconds = 1800;
                persistentRollbackDelayMinutes = 10;
                requiresIndependentConsole = true;
                requiresSeparateRebootAuthorization = true;
                hostSnapshotCreated = true;
                hostRecoveryArmed = false;
                hostRebootPerformed = true;
                evidencePlan = "root/system-manager/validation/2026-09-03-reboot-recovery-live-plan.md";
              };
              liveAttempt = {
                status = "automatic-rollback-verified-cleaned";
                host = "sparkle-01";
                snapshotStamp = "20260902T204546Z";
                operatorRebootPerformed = true;
                bootedAt = "2026-09-02T21:06:03Z";
                rollbackDeadline = "2026-09-02T21:16:04Z";
                firstValidConfirmationAttempt = "2026-09-02T21:16:06Z";
                confirmedBeforeDeadline = false;
                automaticRollbackCompleted = true;
                rollbackVerified = true;
                cleanupCompleted = true;
                currentHostState = "ACTIVE_REGISTERED_GENERATION_TWO_TRIPLE_RETAINED";
                recoverySurface = "absent";
                generationsOneTwoThreeDirectlyRetained = true;
                nixDaemonIdleSocketLessonRecorded = true;
                evidence = "root/system-manager/validation/2026-09-03-reboot-recovery-host-attempt-1.md";
              };
              restoration = {
                status = "generation-three-restored-after-verified-postflight";
                requiredHostState = "ACTIVE_REGISTERED_GENERATION_TWO_TRIPLE_RETAINED";
                program = {
                  repositoryPath = "scripts/root-recovery-restore-generation-three.sh";
                  sha256 = builtins.hashFile "sha256" rootRecoveryRestoreGenerationThreeProgram;
                };
                consoleAcknowledgement = "press-enter-after-local-console-check";
                exactPhraseRequired = false;
                automaticRetentionAfterPostflight = true;
                resumableWhileRollbackTimerActive = true;
                rollbackDelayMinutes = 10;
                preservesAllThreePilotRoots = true;
                performsReboot = false;
                hostRestorationPerformed = true;
                snapshotStamp = "20260903T083058Z";
                repositoryCommit = "1a191e246cbfacbff9946887f7b2b594b4486ff3";
                restoredAt = "2026-09-03T08:31:04Z";
                independentlyVerifiedAt = "2026-09-03T08:35:31Z";
                currentHostState = "ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED";
                automaticPostflightPasses = 2;
                rollbackDisarmed = true;
                rollbackServiceRan = false;
                evidence = "root/system-manager/validation/2026-09-03-restoration-host-attempt-2.md";
                priorAttempt = {
                  snapshotStamp = "20260903T042141Z";
                  generationThreeActivated = true;
                  automaticPostflightPassed = true;
                  retentionConfirmationMatched = false;
                  automaticRollbackCompleted = true;
                  currentHostState = "ACTIVE_REGISTERED_GENERATION_TWO_TRIPLE_RETAINED";
                  evidence = "root/system-manager/validation/2026-09-03-restoration-host-attempt-1.md";
                };
              };
              hostRecoveryArmed = false;
              hostRebootPerformed = true;
            };
          livePilot = {
            status = "generation-three-retained-after-console-confirmation";
            evidencePlan = "root/system-manager/validation/2026-09-02-boot-persistence-live-plan.md";
            requiredPreState = "ACTIVE_REGISTERED_GENERATION_TWO_RETAINED";
            snapshot = {
              root = "inventory/sparkle-01/raw/system-manager-boot-persistence";
              used = "inventory/sparkle-01/raw/system-manager-boot-persistence/20260902T110421Z";
              createdAt = "2026-09-02T11:04:21Z";
              mode = "0700";
              owner = "root";
              maximumAgeSeconds = 1800;
              exactPreStateRequired = true;
            };
            snapshotProgram = {
              repositoryPath = "scripts/snapshot-root-boot-persistence.sh";
              sha256 = builtins.hashFile "sha256" rootBootPersistenceSnapshotProgram;
            };
            activationProgram = {
              repositoryPath = "scripts/activate-root-boot-persistence-pilot.sh";
              sha256 = builtins.hashFile "sha256" rootBootPersistencePilotProgram;
            };
            systemdSnapshotPropertyProgram = {
              repositoryPath = "scripts/systemd-snapshot-property.sh";
              sha256 = builtins.hashFile "sha256" systemdSnapshotPropertyProgram;
            };
            systemdSnapshotPropertyTest = {
              repositoryPath = "scripts/test-systemd-snapshot-property.sh";
              sha256 = builtins.hashFile "sha256" systemdSnapshotPropertyTestProgram;
              check = systemdSnapshotPropertyRegressionCheck.drvPath;
            };
            confirmation = {
              phrase = "KEEP GENERATION THREE";
              timeoutSeconds = 300;
              requiresLocalConsoleVerification = true;
              repeatedPostflightBeforeDisarm = true;
            };
            rollback = {
              timerUnit = "dgx-root-boot-persistence-rollback.timer";
              delayMinutes = 10;
              armedBeforeActivation = true;
              transactionAction = "rollback-boot";
              restoresState = "exact registered and active no-boot generation two";
              preservesAllThreePilotRoots = true;
              survivesHostReboot = false;
            };
            reboot = {
              status = "separate-plan-not-designed-or-authorized";
              performed = false;
              forbiddenDuringActivationWindow = true;
            };
            hostCandidateRetentionPerformed = true;
            hostRegistrationPerformed = true;
            hostActivationPerformed = true;
            hostBootLinkCreated = true;
            hostRebootPerformed = false;
          };
          liveActivation = {
            stateClass = "ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED";
            host = "sparkle-01";
            activatedAt = "2026-09-02T11:16:42Z";
            confirmedAt = "2026-09-02T11:16:50Z";
            repositoryCommit = "2e58f537e92ef0522fb0b9e8748de192fb62d230";
            snapshot = "inventory/sparkle-01/raw/system-manager-boot-persistence/20260902T110421Z";
            evidence = "root/system-manager/validation/2026-09-02-boot-persistence-host-attempt-1.md";
            localConsoleConfirmed = true;
            rollbackDisarmed = true;
            rollbackServiceRan = false;
            protectedServicesUnchanged = true;
            bootLinkCreated = true;
            managedPathCount = 6;
            managedServiceCount = 3;
            stateFileSha256 = "513bc468705ed5322cd50e734172621c5b87aef59af805682ef9ae5f70d5fba8";
            hostRebootPerformed = false;
          };
        };

        desktopController = {
          status = "disposable-lifecycle-passed-live-switch-awaiting";
          selectedFleetMode = sparkleHost.desktop.mode;
          liveHostMode = "factory-gnome";
          hostControllerActivated = false;
          supportedModes = [
            "headless"
            "gnome"
          ];
          candidates = {
            headless = rootDesktopHeadlessGeneration.outPath;
            gnome = rootDesktopGnomeGeneration.outPath;
            rollback = rootTailscaleMigrationGeneration.outPath;
          };
          managedPaths = [
            "/etc/dgx-setup/desktop-mode"
            "/etc/systemd/system/default.target"
            "/etc/systemd/system/dgx-gnome.target"
            "/etc/systemd/system/dgx-headless.target"
          ];
          orchestrationTargets = {
            headless = "dgx-headless.target";
            gnome = "dgx-gnome.target";
          };
          preservesSystemManagerTarget = true;
          preservesTailscale = true;
          ownsFactoryGdm = false;
          ownsFactoryDesktopPackages = false;
          performsRuntimeSwitchDuringActivation = false;
          disposableLifecycleTest =
            let
              observedDrvPath = "/nix/store/qv3v6lglnqigqa60qs3zg4x5qkcy6hsw-container-test-dgx-desktop-mode-lifecycle.drv";
              observedOutputPath = "/nix/store/58ca2p4a20hfsvy5is4dzk0g5zs60rqg-container-test-dgx-desktop-mode-lifecycle";
            in
            {
              verifiedAt = "2026-09-05T11:23:31Z";
              result = "passed";
              inherit observedDrvPath observedOutputPath;
              outputHash = "sha256:109yz2sydf0zp6sqwsqsv9pw53f7lkm0qq7dksd3vw1bys4riypv";
              outputSriHash = "sha256-+/qYifYr8D2anu1gDOqkx43Cb9oaa461uR+45rX4PoE=";
              currentDrvPath = desktopModeLifecycleContainerTest.drvPath;
              currentOutputPath = desktopModeLifecycleContainerTest.outPath;
              matchesCurrent =
                desktopModeLifecycleContainerTest.drvPath == observedDrvPath
                && desktopModeLifecycleContainerTest.outPath == observedOutputPath;
              subtestCount = 10;
              disposableRestarts = 3;
              provesHeadlessPersistence = true;
              provesGnomePersistence = true;
              provesFactoryFallback = true;
              provesTailscaleContinuity = true;
              hostMutation = false;
              hostPostflight = "clean";
            };
          guardedHeadlessTransaction = {
            status = "transaction-primitive-passed-live-operator-awaiting";
            program = {
              repositoryPath = "scripts/root-desktop-mode-transaction.sh";
              sha256 = builtins.hashFile "sha256" rootDesktopModeTransactionProgram;
              actions = [
                "apply-headless"
                "rollback-factory"
                "verify-factory"
                "verify-headless"
              ];
            };
            exactFromGeneration = 4;
            exactToGeneration = 5;
            rollbackMode = "factory-gnome-generation-four";
            retainsAllFivePilotRoots = true;
            preservesTailscaleProcess = true;
            performsReboot = false;
            liveOperator = {
              status = "designed-disposable-lifecycle-awaiting";
              implemented = true;
              repositoryPath = "scripts/dgx-desktop";
              sha256 = builtins.hashFile "sha256" rootDesktopSwitchOperatorProgram;
              actions = [
                "plan"
                "headless"
                "status"
                "confirm"
                "rollback"
                "cleanup-rolled-back"
              ];
              bundle = rootDesktopSwitchBundle.outPath;
              rollbackDelay = "10min";
              rollbackTarget = rootTailscaleMigrationGeneration.outPath;
              candidateRoot = "/nix/var/nix/gcroots/dgx-setup-desktop-headless-pilot";
              rollbackBundleRoot = "/nix/var/nix/gcroots/dgx-setup-desktop-switch-rollback";
              requiresPersistentRollbackBeforeMutation = true;
              detachedWorkerIgnoresIsolation = true;
              exactPhraseRequired = false;
              performsReboot = false;
              isolatedLifecycle = {
                flakeCheck = "desktop-switch-lifecycle-container";
                result = "awaiting-root-local-run";
                hostMutation = false;
              };
            };
            isolatedTest =
              let
                observedDrvPath = "/nix/store/z6nh3w3lv0rqk743b4v6b197q99hrgx3-container-test-dgx-desktop-headless-transaction.drv";
                observedOutputPath = "/nix/store/i82zf8kndgzxszcdmnlncyma2sbb5aj6-container-test-dgx-desktop-headless-transaction";
              in
              {
                flakeCheck = "desktop-headless-transaction-container";
                verifiedAt = "2026-09-05T11:55:21Z";
                repositoryCommit = "71bd7c409909b9be514321ac99a030cf2d536651";
                result = "passed";
                inherit observedDrvPath observedOutputPath;
                outputHash = "sha256:1aabbxcajx50vz49ak43ha0i7hivri6vr9q23ggl9x6crain9aa1";
                outputSriHash = "sha256-Qalko8rM9ETfGwKnvE3MO8ITgYKDTJXI36B0qVhfS6k=";
                currentDrvPath = desktopHeadlessTransactionContainerTest.drvPath;
                currentOutputPath = desktopHeadlessTransactionContainerTest.outPath;
                matchesCurrent =
                  desktopHeadlessTransactionContainerTest.drvPath == observedDrvPath
                  && desktopHeadlessTransactionContainerTest.outPath == observedOutputPath;
                subtestCount = 12;
                provesInjectedFailureRollback = true;
                provesExactHeadlessSwitch = true;
                provesIdempotentFactoryRollback = true;
                provesTailscaleProcessContinuity = true;
                hostMutation = false;
                hostPostflight = "clean";
              };
          };
          evidence = "docs/2026-09-05-desktop-controller-candidates.md";
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
      codexRelease = codexPackage.passthru.release;
      lmstudioRelease = lmstudioPackage.passthru.release;
      zedRelease = zedPackage.passthru.release;

      profilePolicyCheck =
        assert fleetSpec.schemaVersion == 1;
        assert sparkleHost.system == system;
        assert sparkleHost.pilotRing == "pilot";
        assert sparkleArmen.unixName == "n0b0dy";
        assert sparkleArmen.homeDirectory == "/home/n0b0dy";
        assert sparkleHost.fleetBase.enable;
        assert builtins.elem sparkleHost.desktop.mode [
          "headless"
          "gnome"
          "hyprland"
          "kde"
        ];
        assert sparkleHost.access.tailscale.selected;
        assert sparkleHost.access.tailscale.sshDesired;
        assert sparkleHost.access.tailscale.ownership == "nix-managed";
        assert sparkleHost.workloads.isaacOmniverse.selected;
        assert !sparkleHost.workloads.isaacOmniverse.enabled;
        assert !sparkleHost.workloads.lmstudioDaemon.selected;
        assert !sparkleHost.workloads.lmstudioDaemon.enabled;
        assert nixBootstrapSpec.schemaVersion == 1;
        assert nixBootstrapSpec.installer.project == "NixOS/nix-installer";
        assert nixBootstrapSpec.installer.releaseTag == nixBootstrapSpec.installer.version;
        assert nixBootstrapSpec.installer.asset == "nix-installer-aarch64-linux";
        assert
          nixBootstrapSpec.installer.url
          == "https://github.com/NixOS/nix-installer/releases/download/${nixBootstrapSpec.installer.releaseTag}/${nixBootstrapSpec.installer.asset}";
        assert nixBootstrapSpec.installer.size > 0;
        assert builtins.match "[0-9a-f]{64}" nixBootstrapSpec.installer.sha256 != null;
        assert nixBootstrapSpec.installer.embeddedNixVersion == nixBootstrapSpec.installer.version;
        assert nixBootstrapSpec.desiredRuntime.version == "2.35.2";
        assert nixBootstrapSpec.linuxPlanner.init == "systemd";
        assert nixBootstrapSpec.linuxPlanner.startDaemon;
        assert nixBootstrapSpec.linuxPlanner.modifyProfile;
        assert nixBootstrapSpec.linuxPlanner.enableFlakes;
        assert !nixBootstrapSpec.linuxPlanner.addChannel;
        assert basePackageNames == expectedBasePackageNames;
        assert graphicalBasePackageNames == expectedBasePackageNames;
        assert headlessSharedGraphicalPackageNames == [ ];
        assert sharedGraphicalPackageNames == expectedSharedGraphicalPackageNames;
        assert
          packageNames baseProfile.config.dgx.userOverlays.armen.codex.packages
          == expectedArmenAllModesPackageNames;
        assert
          packageNames graphicalProfile.config.dgx.userOverlays.armen.codex.packages
          == expectedArmenAllModesPackageNames;
        assert
          packageNames hyprlandProfile.config.dgx.userOverlays.armen.codex.packages
          == expectedArmenAllModesPackageNames;
        assert
          packageNames hyprlandPortalProfile.config.dgx.userOverlays.armen.codex.packages
          == expectedArmenAllModesPackageNames;
        assert baseProfile.config.dgx.userOverlays.armen.codex.active;
        assert graphicalProfile.config.dgx.userOverlays.armen.codex.active;
        assert hyprlandProfile.config.dgx.userOverlays.armen.codex.active;
        assert hyprlandPortalProfile.config.dgx.userOverlays.armen.codex.active;
        assert
          toString baseProfile.config.home.file.".local/bin/codex".source == "${codexPackage}/bin/codex";
        assert baseProfile.config.home.file.".local/bin/codex".force;
        assert packageNames selectedPersonalGraphicalCandidates == expectedPersonalGraphicalCandidateNames;
        assert personalGraphicalCandidatesAbsentFrom baseProfile;
        assert personalGraphicalCandidatesAbsentFrom graphicalProfile;
        assert personalGraphicalCandidatesAbsentFrom hyprlandProfile;
        assert personalGraphicalCandidatesAbsentFrom hyprlandPortalProfile;
        # A reviewed dependency-update commit is allowed to make the desired
        # candidate differ from the recorded live deployment. The guarded Home
        # transaction, not flake evaluation, owns that later state transition.
        assert lib.hasPrefix "/nix/store/" profileManifests.deployments.sparkle01Home.observedCandidate;
        assert !profileManifests.deployments.sparkle01Home.userSystemdEnabled;
        assert !profileManifests.deployments.sparkle01Home.rollbackArmed;
        assert profileManifests.deployments.sparkle01Home.realRollbackPassed;
        assert profileManifests.services.tailscale.ownershipState == "nix-managed";
        assert profileManifests.deployments.sparkle01Tailscale.matchesCurrent;
        assert profileManifests.deployments.sparkle01Tailscale.profileGeneration == 4;
        assert profileManifests.deployments.sparkle01Tailscale.mutableIdentityPreserved;
        assert profileManifests.deployments.sparkle01Tailscale.tailscaleSshReconnectVerified;
        assert profileManifests.deployments.sparkle01Tailscale.rebootVerified;
        assert !profileManifests.deployments.sparkle01Tailscale.rollbackArmed;
        assert profileManifests.deployments.sparkle01Tailscale.aptFallbackRetained;
        assert graphicalPackageNames == expectedGraphicalPackageNames;
        assert !baseProfile.config.xdg.enable;
        assert !baseProfile.config.xdg.mime.enable;
        assert !baseProfile.config.xdg.mimeApps.enable;
        assert !baseProfile.config.xdg.userDirs.enable;
        assert !baseProfile.config.xdg.portal.enable;
        assert !baseProfile.config.systemd.user.enable;
        assert !baseProfile.config.programs.home-manager.enable;
        assert !baseProfile.config.programs.man.enable;
        assert !baseProfile.config.programs.man.man-db.enable;
        assert !baseProfile.config.manual.manpages.enable;
        assert !baseProfile.config.dgx.userOverlays.armen.graphical.active;
        assert baseProfile.config.dgx.userOverlays.armen.codex.relaxedPermissions.active;
        assert
          baseProfile.config.dgx.userOverlays.armen.codex.relaxedPermissions.policy.approval_policy
          == "never";
        assert
          baseProfile.config.dgx.userOverlays.armen.codex.relaxedPermissions.policy.default_permissions
          == ":danger-full-access";
        assert
          baseProfile.config.dgx.userOverlays.armen.codex.relaxedPermissions.policy.approvals_reviewer
          == "auto_review";
        assert
          !baseProfile.config.dgx.userOverlays.armen.codex.relaxedPermissions.policy.check_for_update_on_startup;
        assert
          baseProfile.config.dgx.userOverlays.armen.codex.relaxedPermissions.policy.notice.hide_full_access_warning;
        assert
          baseProfile.config.dgx.userOverlays.armen.codex.relaxedPermissions.policy.apps._default.default_tools_approval_mode
          == "approve";
        assert
          baseProfile.config.dgx.userOverlays.armen.codex.relaxedPermissions.policy.apps._default.destructive_enabled;
        assert
          baseProfile.config.dgx.userOverlays.armen.codex.relaxedPermissions.policy.apps._default.open_world_enabled;
        assert graphicalProfile.config.xdg.enable;
        assert graphicalProfile.config.xdg.mime.enable;
        assert graphicalProfile.config.systemd.user.enable;
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

      codexPolicyCheck =
        assert codexRelease.architecture == "aarch64-unknown-linux-musl";
        assert codexRelease.asset == "codex-package-aarch64-unknown-linux-musl.tar.gz";
        assert codexRelease.releaseTag == "rust-v${codexRelease.version}";
        assert builtins.match "[0-9a-f]{64}" codexRelease.upstreamSha256 != null;
        assert lib.getName codexPackage == "codex-cli";
        pkgs.runCommand "dgx-codex-cli-policy" { } ''
          test -x ${codexPackage}/bin/codex
          test -x ${codexPackage}/bin/codex-code-mode-host
          test -x ${codexPackage}/codex-path/rg
          test -x ${codexPackage}/codex-resources/bwrap
          test "$(${codexPackage}/bin/codex --version)" = \
            "codex-cli ${codexRelease.version}"
          touch "$out"
        '';

      chromiumPolicyCheck =
        assert lib.getName chromiumPackage == "chromium";
        assert packageIsFree chromiumPackage;
        pkgs.runCommand "dgx-chromium-policy" { } ''
          test -x ${chromiumPackage}/bin/chromium
          ${chromiumPackage}/bin/chromium --version | \
            grep -E '^Chromium ${chromiumPackage.version}[[:space:]]*$'
          test -x ${chromiumSandboxPackage}/bin/__chromium-suid-sandbox
          test "$(stat -c %a ${chromiumSandboxPackage}/bin/__chromium-suid-sandbox)" = 555
          grep -F '/run/wrappers/bin/__chromium-suid-sandbox' \
            ${chromiumPackage}/bin/chromium
          grep -F '${chromiumSandboxPackage}/bin/__chromium-suid-sandbox' \
            ${chromiumPackage}/bin/chromium
          test -f ${chromiumPackage}/share/applications/chromium-browser.desktop
          grep -Fx 'Exec=chromium %U' \
            ${chromiumPackage}/share/applications/chromium-browser.desktop
          test ! -e ${chromiumPackage}/etc
          test ! -e ${chromiumPackage}/lib/systemd
          test ! -e ${chromiumPackage}/share/autostart
          touch "$out"
        '';

      lmstudioPolicyCheck =
        assert lmstudioPackage.version == lmstudioRelease.version;
        assert lmstudioRelease.architecture == "arm64";
        assert lmstudioRelease.format == "AppImage";
        assert lmstudioPackage.avoidsUserNamespaceWrapper;
        assert lmstudioPackage.desktopUsesFactoryLinuxRuntime;
        assert lmstudioPackage.lmsUsesFactoryGlibcLoader;
        assert
          lmstudioRelease.url
          == "https://installers.lmstudio.ai/linux/arm64/${lmstudioRelease.version}/LM-Studio-${lmstudioRelease.version}-arm64.AppImage";
        assert lib.getName lmstudioPackage == "lmstudio";
        pkgs.runCommand "dgx-lmstudio-policy" { nativeBuildInputs = [ pkgs.binutils ]; } ''
          test -x ${lmstudioPackage}/bin/lm-studio
          test -x ${lmstudioPackage}/bin/lms
          test -x ${lmstudioPackage}/libexec/lmstudio-AppRun
          test -x ${lmstudioPackage}/libexec/lms-real
          grep -F 'APPDIR=' ${lmstudioPackage}/bin/lm-studio
          test "$(readelf -l ${lmstudioPackage}/libexec/lms-real | \
            sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p')" = \
            /lib/ld-linux-aarch64.so.1
          grep -F 'LD_LIBRARY_PATH' ${lmstudioPackage}/bin/lms
          test -f ${lmstudioPackage}/share/applications/ai.elementlabs.lmstudio.desktop
          grep -Fx 'Exec=lm-studio %U' \
            ${lmstudioPackage}/share/applications/ai.elementlabs.lmstudio.desktop
          test ! -e ${lmstudioPackage}/etc
          test ! -e ${lmstudioPackage}/lib/systemd
          test ! -e ${lmstudioPackage}/share/autostart
          touch "$out"
        '';

      zedPolicyCheck =
        assert zedPackage.version == zedRelease.version;
        assert zedRelease.architecture == "aarch64";
        assert zedRelease.asset == "zed-linux-aarch64.tar.gz";
        assert zedRelease.releaseTag == "v${zedRelease.version}";
        assert builtins.match "[0-9a-f]{40}" zedRelease.tagCommit != null;
        assert builtins.match "[0-9a-f]{64}" zedRelease.upstreamSha256 != null;
        assert zedPackage.usesFactoryLinuxRuntime;
        assert lib.getName zedPackage == "zed-editor";
        pkgs.runCommand "dgx-zed-policy" { nativeBuildInputs = [ pkgs.binutils ]; } ''
          test -x ${zedPackage}/bin/zed
          test -x ${zedPackage}/bin/.zed-unwrapped
          test -x ${zedPackage}/libexec/zed-editor
          test -f ${zedPackage}/share/applications/dev.zed.Zed.desktop
          grep -F 'ZED_UPDATE_EXPLANATION' ${zedPackage}/bin/zed
          test "$(readelf -l ${zedPackage}/bin/.zed-unwrapped | \
            sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p')" = \
            /lib/ld-linux-aarch64.so.1
          test "$(readelf -l ${zedPackage}/libexec/zed-editor | \
            sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p')" = \
            /lib/ld-linux-aarch64.so.1
          test ! -e ${zedPackage}/etc
          test ! -e ${zedPackage}/lib/systemd
          test ! -e ${zedPackage}/share/autostart
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
        assert rootTailscaleMigrationConfig.dgx.root.bootPersistence.enable;
        assert rootTailscaleMigrationConfig.dgx.root.tailscale.enable;
        assert rootTailscaleMigrationConfig.dgx.root.tailscale.sshDesired;
        assert rootTailscaleMigrationConfig.dgx.root.tailscale.package == tailscalePackage;
        assert rootTailscaleMigrationServiceNames == expectedRootTailscaleMigrationServiceNames;
        assert rootTailscaleMigrationEtcNames == expectedRootCanaryEtcNames;
        assert rootTailscaleMigrationPackageNames == [ ];
        assert rootTailscaleMigrationGeneration.outPath != rootCanaryBootPersistenceGeneration.outPath;
        assert rootTailscaleMigrationConfig.systemd.services.tailscaled.wantedBy == [ "multi-user.target" ];
        assert
          rootTailscaleMigrationConfig.systemd.services.tailscaled.serviceConfig.ExecStart
          == "${tailscalePackage}/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock --port=\${PORT} $FLAGS";
        pkgs.runCommand "dgx-tailscale-policy" { } ''
          units="$(${rootPkgs.coreutils}/bin/readlink -f -- \
            ${rootTailscaleMigrationConfig.build.etc.staticEnv}/systemd/system)"
          test -L "$units/tailscaled.service"
          test -L "$units/system-manager.target.wants/tailscaled.service"
          test "$(${rootPkgs.coreutils}/bin/readlink -- \
            "$units/system-manager.target.wants/tailscaled.service")" = \
            ../tailscaled.service
          grep -F '${tailscalePackage}/bin/tailscaled' \
            "$units/tailscaled.service"
          grep -F '/var/lib/tailscale/tailscaled.state' \
            "$units/tailscaled.service"
          grep -F '/run/tailscale/tailscaled.sock' \
            "$units/tailscaled.service"
          grep -F 'EnvironmentFile=-/etc/dgx-setup/tailscaled.env' \
            "$units/tailscaled.service"
          test -x ${rootTailscaleMigrationBundle}/bin/dgx-root-tailscale-migration
          grep -F 'OnActiveSec=10min' \
            ${rootTailscaleMigrationBundle}/lib/systemd/system/dgx-tailscale-migration-rollback.timer
          grep -F 'ConditionPathExists=/var/lib/dgx-setup/tailscale-migration/armed' \
            ${rootTailscaleMigrationBundle}/lib/systemd/system/dgx-tailscale-migration-rollback.timer
          grep -F '${rootCanaryBootPersistenceGeneration}' \
            ${rootTailscaleMigrationBundle}/bin/dgx-root-tailscale-migration
          grep -F '${rootTailscaleMigrationGeneration}' \
            ${rootTailscaleMigrationBundle}/bin/dgx-root-tailscale-migration
          grep -F 'MIGRATION_STATUS=AWAITING_REBOOT' \
            ${./scripts/dgx-tailscale}
          grep -F 'one guarded reboot is required before confirmation' \
            ${./scripts/dgx-tailscale}
          touch "$out"
        '';

      desktopControllerPolicyCheck =
        assert rootDesktopHeadlessConfig.dgx.root.bootPersistence.enable;
        assert rootDesktopHeadlessConfig.dgx.root.tailscale.enable;
        assert rootDesktopHeadlessConfig.dgx.root.desktop.enable;
        assert rootDesktopHeadlessConfig.dgx.root.desktop.mode == "headless";
        assert rootDesktopGnomeConfig.dgx.root.bootPersistence.enable;
        assert rootDesktopGnomeConfig.dgx.root.tailscale.enable;
        assert rootDesktopGnomeConfig.dgx.root.desktop.enable;
        assert rootDesktopGnomeConfig.dgx.root.desktop.mode == "gnome";
        assert rootDesktopHeadlessServiceNames == expectedRootDesktopServiceNames;
        assert rootDesktopGnomeServiceNames == expectedRootDesktopServiceNames;
        assert rootDesktopHeadlessEtcNames == expectedRootDesktopEtcNames;
        assert rootDesktopGnomeEtcNames == expectedRootDesktopEtcNames;
        assert rootDesktopHeadlessPackageNames == [ ];
        assert rootDesktopGnomePackageNames == [ ];
        assert rootDesktopHeadlessGeneration.outPath != rootTailscaleMigrationGeneration.outPath;
        assert rootDesktopGnomeGeneration.outPath != rootTailscaleMigrationGeneration.outPath;
        assert rootDesktopHeadlessGeneration.outPath != rootDesktopGnomeGeneration.outPath;
        assert !(builtins.hasAttr "gdm.service" rootDesktopHeadlessConfig.systemd.units);
        assert !(builtins.hasAttr "gdm.service" rootDesktopGnomeConfig.systemd.units);
        assert !(builtins.hasAttr "display-manager.service" rootDesktopHeadlessConfig.systemd.units);
        assert !(builtins.hasAttr "display-manager.service" rootDesktopGnomeConfig.systemd.units);
        rootPkgs.runCommand "dgx-desktop-controller-policy" { } ''
          headless_units="$(${rootPkgs.coreutils}/bin/readlink -f -- \
            ${rootDesktopHeadlessConfig.build.etc.staticEnv}/systemd/system)"
          gnome_units="$(${rootPkgs.coreutils}/bin/readlink -f -- \
            ${rootDesktopGnomeConfig.build.etc.staticEnv}/systemd/system)"

          test -L "$headless_units/default.target"
          test -L "$gnome_units/default.target"
          grep -Fx 'Requires=dgx-headless.target' \
            "$headless_units/default.target"
          grep -Fx 'After=dgx-headless.target' \
            "$headless_units/default.target"
          grep -Fx 'Requires=dgx-gnome.target' \
            "$gnome_units/default.target"
          grep -Fx 'After=dgx-gnome.target' \
            "$gnome_units/default.target"

          grep -Fx 'Requires=multi-user.target system-manager.target' \
            "$headless_units/dgx-headless.target"
          grep -Fx 'Conflicts=dgx-gnome.target graphical.target' \
            "$headless_units/dgx-headless.target"
          grep -Fx 'AllowIsolate=true' "$headless_units/dgx-headless.target"
          grep -Fx 'Requires=graphical.target system-manager.target' \
            "$gnome_units/dgx-gnome.target"
          grep -Fx 'Conflicts=dgx-headless.target' \
            "$gnome_units/dgx-gnome.target"
          grep -Fx 'AllowIsolate=true' "$gnome_units/dgx-gnome.target"

          test ! -e "$headless_units/gdm.service"
          test ! -e "$headless_units/display-manager.service"
          test ! -e "$gnome_units/gdm.service"
          test ! -e "$gnome_units/display-manager.service"

          # A pure Nix builder cannot create systemd's hard-coded
          # /run/systemd manager directory. Parse the same portable unit
          # directives through a private user-manager runtime here; the
          # disposable lifecycle check below verifies them as real system
          # units inside a booted Ubuntu container.
          verification_units="$TMPDIR/dgx-desktop-verification-units"
          verification_runtime="$TMPDIR/dgx-desktop-verification-runtime"
          mkdir -p "$verification_units" "$verification_runtime/systemd"
          printf '[Unit]\nDescription=Hermetic basic target fixture\n' \
            >"$verification_units/basic.target"
          XDG_RUNTIME_DIR="$verification_runtime" \
            SYSTEMD_UNIT_PATH="${rootDesktopSwitchBundle}/lib/systemd/system:$verification_units" \
            ${rootPkgs.systemd}/bin/systemd-analyze --user verify \
              ${rootDesktopSwitchBundle}/lib/systemd/system/dgx-desktop-switch-rollback.service \
              ${rootDesktopSwitchBundle}/lib/systemd/system/dgx-desktop-switch-rollback.timer
          test -x ${rootDesktopSwitchBundle}/bin/dgx-root-desktop-switch
          grep -Fx \
            'ExecStart=${rootDesktopSwitchBundle}/bin/dgx-root-desktop-switch rollback-guarded' \
            ${rootDesktopSwitchBundle}/lib/systemd/system/dgx-desktop-switch-rollback.service
          grep -Fx 'IgnoreOnIsolate=yes' \
            ${rootDesktopSwitchBundle}/lib/systemd/system/dgx-desktop-switch-rollback.service
          grep -Fx 'IgnoreOnIsolate=yes' \
            ${rootDesktopSwitchBundle}/lib/systemd/system/dgx-desktop-switch-rollback.timer
          grep -Fx 'OnActiveSec=10min' \
            ${rootDesktopSwitchBundle}/lib/systemd/system/dgx-desktop-switch-rollback.timer
          touch "$out"
        '';

      tailscaleMigrationShellCheck =
        rootPkgs.runCommand "dgx-tailscale-migration-shellcheck"
          {
            nativeBuildInputs = [ rootPkgs.shellcheck ];
          }
          ''
            shellcheck \
              ${./scripts/dgx-desktop} \
              ${./scripts/dgx-home} \
              ${./scripts/dgx-setup} \
              ${./scripts/dgx-tailscale} \
              ${./scripts/test-dgx-setup-apply.sh} \
              ${./scripts/test-dgx-setup-plan.sh} \
              ${./scripts/test-desktop-headless-transaction.sh} \
              ${./scripts/test-desktop-mode-lifecycle.sh} \
              ${./scripts/test-desktop-switch-lifecycle.sh} \
              ${./scripts/test-post-tailscale-integration.sh} \
              ${./scripts/test-tailscale-unit-lifecycle.sh} \
              ${./.agents/skills/dgx-spark-ops/scripts/audit-updates.sh}
            # This transaction intentionally names the exact common path set
            # next to its unit set; the assertions below consume the paths
            # individually rather than iterating that documentation array.
            shellcheck --exclude=SC2034 \
              ${rootTailscaleMigrationTransactionProgram} \
              ${rootDesktopModeTransactionProgram}
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
        assert rootManagerManifest.foundationNixpkgs.policy == "frozen-live-root-lane";
        assert rootManagerManifest.foundationNixpkgs.rev == "a9e6d84f9c2f9012f5fe7d964a7851352300e61a";
        assert !rootManagerManifest.foundationNixpkgs.advancesWithUserPackages;
        assert
          rootManagerManifest.desktopController.status == "disposable-lifecycle-passed-live-switch-awaiting";
        assert rootManagerManifest.desktopController.selectedFleetMode == "headless";
        assert rootManagerManifest.desktopController.liveHostMode == "factory-gnome";
        assert !rootManagerManifest.desktopController.hostControllerActivated;
        assert
          rootManagerManifest.desktopController.supportedModes == [
            "headless"
            "gnome"
          ];
        assert rootManagerManifest.desktopController.preservesSystemManagerTarget;
        assert rootManagerManifest.desktopController.preservesTailscale;
        assert !rootManagerManifest.desktopController.ownsFactoryGdm;
        assert !rootManagerManifest.desktopController.ownsFactoryDesktopPackages;
        assert !rootManagerManifest.desktopController.performsRuntimeSwitchDuringActivation;
        assert rootManagerManifest.desktopController.disposableLifecycleTest.result == "passed";
        assert rootManagerManifest.desktopController.disposableLifecycleTest.matchesCurrent;
        assert rootManagerManifest.desktopController.disposableLifecycleTest.subtestCount == 10;
        assert rootManagerManifest.desktopController.disposableLifecycleTest.disposableRestarts == 3;
        assert rootManagerManifest.desktopController.disposableLifecycleTest.provesHeadlessPersistence;
        assert rootManagerManifest.desktopController.disposableLifecycleTest.provesGnomePersistence;
        assert rootManagerManifest.desktopController.disposableLifecycleTest.provesFactoryFallback;
        assert rootManagerManifest.desktopController.disposableLifecycleTest.provesTailscaleContinuity;
        assert !rootManagerManifest.desktopController.disposableLifecycleTest.hostMutation;
        assert rootManagerManifest.desktopController.disposableLifecycleTest.hostPostflight == "clean";
        assert
          rootManagerManifest.desktopController.guardedHeadlessTransaction.status
          == "transaction-primitive-passed-live-operator-awaiting";
        assert
          rootManagerManifest.desktopController.guardedHeadlessTransaction.program.sha256
          == reviewedRootDesktopModeTransactionSha256;
        assert
          rootManagerManifest.desktopController.guardedHeadlessTransaction.program.actions == [
            "apply-headless"
            "rollback-factory"
            "verify-factory"
            "verify-headless"
          ];
        assert rootManagerManifest.desktopController.guardedHeadlessTransaction.exactFromGeneration == 4;
        assert rootManagerManifest.desktopController.guardedHeadlessTransaction.exactToGeneration == 5;
        assert rootManagerManifest.desktopController.guardedHeadlessTransaction.retainsAllFivePilotRoots;
        assert rootManagerManifest.desktopController.guardedHeadlessTransaction.preservesTailscaleProcess;
        assert !rootManagerManifest.desktopController.guardedHeadlessTransaction.performsReboot;
        assert
          rootManagerManifest.desktopController.guardedHeadlessTransaction.liveOperator.requiresPersistentRollbackBeforeMutation;
        assert
          rootManagerManifest.desktopController.guardedHeadlessTransaction.liveOperator.status
          == "designed-disposable-lifecycle-awaiting";
        assert rootManagerManifest.desktopController.guardedHeadlessTransaction.liveOperator.implemented;
        assert
          rootManagerManifest.desktopController.guardedHeadlessTransaction.liveOperator.sha256
          == reviewedRootDesktopSwitchOperatorSha256;
        assert
          rootManagerManifest.desktopController.guardedHeadlessTransaction.liveOperator.actions == [
            "plan"
            "headless"
            "status"
            "confirm"
            "rollback"
            "cleanup-rolled-back"
          ];
        assert
          rootManagerManifest.desktopController.guardedHeadlessTransaction.liveOperator.bundle
          == rootDesktopSwitchBundle.outPath;
        assert
          rootManagerManifest.desktopController.guardedHeadlessTransaction.liveOperator.detachedWorkerIgnoresIsolation;
        assert
          !rootManagerManifest.desktopController.guardedHeadlessTransaction.liveOperator.exactPhraseRequired;
        assert
          !rootManagerManifest.desktopController.guardedHeadlessTransaction.liveOperator.performsReboot;
        assert
          rootManagerManifest.desktopController.guardedHeadlessTransaction.liveOperator.isolatedLifecycle.result
          == "awaiting-root-local-run";
        assert
          !rootManagerManifest.desktopController.guardedHeadlessTransaction.liveOperator.isolatedLifecycle.hostMutation;
        assert
          rootManagerManifest.desktopController.guardedHeadlessTransaction.isolatedTest.subtestCount == 12;
        assert
          rootManagerManifest.desktopController.guardedHeadlessTransaction.isolatedTest.result == "passed";
        assert rootManagerManifest.desktopController.guardedHeadlessTransaction.isolatedTest.matchesCurrent;
        assert
          rootManagerManifest.desktopController.guardedHeadlessTransaction.isolatedTest.provesInjectedFailureRollback;
        assert
          rootManagerManifest.desktopController.guardedHeadlessTransaction.isolatedTest.provesExactHeadlessSwitch;
        assert
          rootManagerManifest.desktopController.guardedHeadlessTransaction.isolatedTest.provesIdempotentFactoryRollback;
        assert
          rootManagerManifest.desktopController.guardedHeadlessTransaction.isolatedTest.provesTailscaleProcessContinuity;
        assert !rootManagerManifest.desktopController.guardedHeadlessTransaction.isolatedTest.hostMutation;
        assert
          rootManagerManifest.desktopController.guardedHeadlessTransaction.isolatedTest.hostPostflight
          == "clean";
        assert rootCanaryConfig.nixpkgs.hostPlatform == system;
        assert rootCanaryServiceNames == expectedRootCanaryServiceNames;
        assert rootCanaryEtcNames == expectedRootCanaryEtcNames;
        assert rootCanaryPackageNames == [ ];
        assert rootCanaryRegistrationTestServiceNames == expectedRootCanaryServiceNames;
        assert rootCanaryRegistrationTestEtcNames == expectedRootCanaryEtcNames;
        assert rootCanaryRegistrationTestPackageNames == [ ];
        assert rootCanaryRegistrationTestGeneration.outPath != rootCanary.outPath;
        assert rootCanaryBootPersistenceServiceNames == expectedRootCanaryServiceNames;
        assert rootCanaryBootPersistenceEtcNames == expectedRootCanaryEtcNames;
        assert rootCanaryBootPersistencePackageNames == [ ];
        assert !rootCanaryConfig.dgx.root.tailscale.enable;
        assert !rootCanaryRegistrationTestConfig.dgx.root.tailscale.enable;
        assert !rootCanaryBootPersistenceConfig.dgx.root.tailscale.enable;
        assert rootCanaryBootPersistenceGeneration.outPath != rootCanaryRegistrationTestGeneration.outPath;
        assert !rootCanaryConfig.nix.enable;
        assert !rootCanaryRegistrationTestConfig.nix.enable;
        assert !rootCanaryBootPersistenceConfig.nix.enable;
        assert !rootCanaryRegistrationTestConfig.dgx.root.bootPersistence.enable;
        assert !rootCanaryRegistrationTestConfig.services.userborn.enable;
        assert !rootCanaryRegistrationTestConfig.security.enableWrappers;
        assert !rootCanaryRegistrationTestConfig.system-manager.linkCurrentSystem;
        assert rootCanaryRegistrationTestConfig.systemd.targets.system-manager.wantedBy == [ ];
        assert rootCanaryBootPersistenceConfig.dgx.root.bootPersistence.enable;
        assert !rootCanaryBootPersistenceConfig.system-manager.linkCurrentSystem;
        assert
          rootCanaryBootPersistenceConfig.systemd.targets.system-manager.wantedBy == [ "default.target" ];
        assert
          rootCanaryBootPersistenceConfig.build.services == rootCanaryRegistrationTestConfig.build.services;
        assert
          rootCanaryBootPersistenceConfig.environment.etc."dgx-setup/canary".text
          == rootCanaryRegistrationTestConfig.environment.etc."dgx-setup/canary".text
          + "boot-persistence-generation=3\n";
        assert rootManagerManifest.registration.isolatedLifecycleTest.result == "passed";
        assert rootManagerManifest.registration.isolatedLifecycleTest.matchesCurrent;
        assert rootManagerManifest.registration.isolatedLifecycleTest.hostPostflight == "clean";
        assert !rootManagerManifest.registration.isolatedLifecycleTest.hostRegistrationPerformed;
        assert !rootManagerManifest.registration.isolatedLifecycleTest.hostActivationPerformed;
        assert
          builtins.hashFile "sha256" rootRegistrationTransactionProgram
          == reviewedRootRegistrationTransactionSha256;
        assert
          builtins.hashFile "sha256" rootGenerationSwitchTransactionProgram
          == reviewedRootGenerationSwitchTransactionSha256;
        assert
          builtins.hashFile "sha256" rootBootPersistenceTransactionProgram
          == reviewedRootBootPersistenceTransactionSha256;
        assert
          builtins.hashFile "sha256" rootBootPersistenceSnapshotProgram
          == reviewedRootBootPersistenceSnapshotSha256;
        assert
          builtins.hashFile "sha256" rootBootPersistencePilotProgram
          == reviewedRootBootPersistencePilotSha256;
        assert builtins.hashFile "sha256" rootCanaryAuditProgram == reviewedRootCanaryAuditSha256;
        assert
          builtins.hashFile "sha256" rootRebootRecoveryTransactionProgram
          == reviewedRootRebootRecoveryTransactionSha256;
        assert
          builtins.hashFile "sha256" rootRebootRecoverySnapshotProgram
          == reviewedRootRebootRecoverySnapshotSha256;
        assert
          builtins.hashFile "sha256" rootRebootRecoveryPilotProgram == reviewedRootRebootRecoveryPilotSha256;
        assert
          builtins.hashFile "sha256" rootRebootRecoveryOperatorProgram
          == reviewedRootRebootRecoveryOperatorSha256;
        assert
          builtins.hashFile "sha256" rootRecoveryRestoreGenerationThreeProgram
          == reviewedRootRecoveryRestoreGenerationThreeSha256;
        assert
          builtins.hashFile "sha256" rootGenerationSwitchSnapshotProgram
          == reviewedRootGenerationSwitchSnapshotSha256;
        assert
          builtins.hashFile "sha256" rootGenerationSwitchPilotProgram
          == reviewedRootGenerationSwitchPilotSha256;
        assert
          builtins.hashFile "sha256" rootDesktopModeTransactionProgram
          == reviewedRootDesktopModeTransactionSha256;
        assert
          builtins.hashFile "sha256" systemdSnapshotPropertyProgram == reviewedSystemdSnapshotPropertySha256;
        assert
          builtins.hashFile "sha256" systemdSnapshotPropertyTestProgram
          == reviewedSystemdSnapshotPropertyTestSha256;
        assert
          rootManagerManifest.registration.guardedFirstGeneration.status
          == "completed-first-generation-registration-retained";
        assert rootManagerManifest.registration.guardedFirstGeneration.requiresActiveUnregisteredCanary;
        assert rootManagerManifest.registration.guardedFirstGeneration.preservesLiveActivation;
        assert rootManagerManifest.registration.guardedFirstGeneration.preservesPilotRetention;
        assert !rootManagerManifest.registration.guardedFirstGeneration.createsBootLink;
        assert !rootManagerManifest.registration.guardedFirstGeneration.restartsServices;
        assert rootManagerManifest.registration.guardedFirstGeneration.liveRegistrationPerformed;
        assert
          rootManagerManifest.registration.guardedFirstGeneration.liveRegistration.stateClass
          == "ACTIVE_REGISTERED_RETAINED";
        assert
          rootManagerManifest.registration.guardedFirstGeneration.liveRegistration.host == "sparkle-01";
        assert
          rootManagerManifest.registration.guardedFirstGeneration.liveRegistration.localConsoleConfirmed;
        assert rootManagerManifest.registration.guardedFirstGeneration.liveRegistration.rollbackDisarmed;
        assert
          rootManagerManifest.registration.guardedFirstGeneration.isolatedTransactionTest.result == "passed";
        assert
          rootManagerManifest.registration.guardedFirstGeneration.isolatedTransactionTest.matchesCurrent;
        assert
          rootManagerManifest.registration.guardedFirstGeneration.isolatedTransactionTest.hostPostflight
          == "clean";
        assert
          !rootManagerManifest.registration.guardedFirstGeneration.isolatedTransactionTest.hostRegistrationPerformed;
        assert
          !rootManagerManifest.registration.guardedFirstGeneration.isolatedTransactionTest.hostActivationPerformed;
        assert
          rootManagerManifest.registration.guardedGenerationSwitch.status
          == "live-generation-two-registered-retained";
        assert
          rootManagerManifest.registration.guardedGenerationSwitch.requiredHostState
          == "ACTIVE_REGISTERED_RETAINED";
        assert
          rootManagerManifest.registration.guardedGenerationSwitch.currentHostState
          == "ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED";
        assert rootManagerManifest.registration.guardedGenerationSwitch.preservesGenerationOne;
        assert rootManagerManifest.registration.guardedGenerationSwitch.preservesBothPilotRoots;
        assert !rootManagerManifest.registration.guardedGenerationSwitch.createsBootLink;
        assert !rootManagerManifest.registration.guardedGenerationSwitch.changesServiceOwnership;
        assert rootManagerManifest.registration.guardedGenerationSwitch.hostGenerationTwoRetentionPerformed;
        assert rootManagerManifest.registration.guardedGenerationSwitch.liveSwitchPerformed;
        assert
          rootManagerManifest.registration.guardedGenerationSwitch.livePilot.status
          == "generation-two-retained-after-console-confirmation";
        assert
          rootManagerManifest.registration.guardedGenerationSwitch.livePilot.snapshot.maximumAgeSeconds
          == 1800;
        assert
          rootManagerManifest.registration.guardedGenerationSwitch.livePilot.rollback.delayMinutes == 10;
        assert
          rootManagerManifest.registration.guardedGenerationSwitch.livePilot.rollback.armedBeforeSwitch;
        assert
          rootManagerManifest.registration.guardedGenerationSwitch.livePilot.rollback.preservesBothPilotRoots;
        assert
          rootManagerManifest.registration.guardedGenerationSwitch.livePilot.confirmation.phrase
          == "KEEP GENERATION TWO";
        assert
          rootManagerManifest.registration.guardedGenerationSwitch.livePilot.confirmation.repeatedPostflightBeforeDisarm;
        assert !rootManagerManifest.registration.guardedGenerationSwitch.livePilot.createsBootLink;
        assert !rootManagerManifest.registration.guardedGenerationSwitch.livePilot.changesServiceOwnership;
        assert
          rootManagerManifest.registration.guardedGenerationSwitch.livePilot.hostGenerationTwoRetentionPerformed;
        assert rootManagerManifest.registration.guardedGenerationSwitch.livePilot.liveSwitchPerformed;
        assert
          rootManagerManifest.registration.guardedGenerationSwitch.liveSwitch.stateClass
          == "ACTIVE_REGISTERED_GENERATION_TWO_RETAINED";
        assert rootManagerManifest.registration.guardedGenerationSwitch.liveSwitch.host == "sparkle-01";
        assert rootManagerManifest.registration.guardedGenerationSwitch.liveSwitch.localConsoleConfirmed;
        assert rootManagerManifest.registration.guardedGenerationSwitch.liveSwitch.rollbackDisarmed;
        assert !rootManagerManifest.registration.guardedGenerationSwitch.liveSwitch.rollbackServiceRan;
        assert !rootManagerManifest.registration.guardedGenerationSwitch.liveSwitch.bootLinkCreated;
        assert
          rootManagerManifest.registration.guardedGenerationSwitch.isolatedTransactionTest.result == "passed";
        assert
          rootManagerManifest.registration.guardedGenerationSwitch.isolatedTransactionTest.matchesCurrent;
        assert
          rootManagerManifest.registration.guardedGenerationSwitch.isolatedTransactionTest.hostPostflight
          == "clean";
        assert
          !rootManagerManifest.registration.guardedGenerationSwitch.isolatedTransactionTest.hostRegistrationPerformed;
        assert
          !rootManagerManifest.registration.guardedGenerationSwitch.isolatedTransactionTest.hostActivationPerformed;
        assert
          !rootManagerManifest.registration.guardedGenerationSwitch.isolatedTransactionTest.hostCandidateRetentionPerformed;
        assert rootManagerManifest.bootPersistence.status == "live-generation-three-boot-linked-retained";
        assert
          rootManagerManifest.bootPersistence.currentHostState
          == "ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED";
        assert rootManagerManifest.bootPersistence.delta.serviceInventoryUnchanged;
        assert rootManagerManifest.bootPersistence.delta.globalPackagesUnchanged;
        assert !rootManagerManifest.bootPersistence.delta.linksCurrentSystem;
        assert
          rootManagerManifest.bootPersistence.transactionProgram.sha256
          == reviewedRootBootPersistenceTransactionSha256;
        assert rootManagerManifest.bootPersistence.retention.hostCreated;
        assert rootManagerManifest.bootPersistence.retention.requiredBeforeTransaction;
        assert rootManagerManifest.bootPersistence.retention.preservedByRollback;
        assert rootManagerManifest.bootPersistence.isolatedTransactionTest.result == "passed";
        assert rootManagerManifest.bootPersistence.isolatedTransactionTest.matchesCurrent;
        assert rootManagerManifest.bootPersistence.isolatedTransactionTest.hostPostflight == "clean";
        assert rootManagerManifest.bootPersistence.isolatedTransactionTest.disposableRestarts == 2;
        assert rootManagerManifest.bootPersistence.isolatedTransactionTest.provesBootStart;
        assert rootManagerManifest.bootPersistence.isolatedTransactionTest.provesRollbackNoBoot;
        assert !rootManagerManifest.bootPersistence.isolatedTransactionTest.hostRegistrationPerformed;
        assert !rootManagerManifest.bootPersistence.isolatedTransactionTest.hostActivationPerformed;
        assert !rootManagerManifest.bootPersistence.isolatedTransactionTest.hostCandidateRetentionPerformed;
        assert !rootManagerManifest.bootPersistence.isolatedTransactionTest.hostBootLinkCreated;
        assert !rootManagerManifest.bootPersistence.isolatedTransactionTest.hostRebootPerformed;
        assert
          rootManagerManifest.bootPersistence.livePilot.status
          == "generation-three-retained-after-console-confirmation";
        assert
          rootManagerManifest.bootPersistence.livePilot.snapshotProgram.sha256
          == reviewedRootBootPersistenceSnapshotSha256;
        assert
          rootManagerManifest.bootPersistence.livePilot.activationProgram.sha256
          == reviewedRootBootPersistencePilotSha256;
        assert
          rootManagerManifest.bootPersistence.livePilot.systemdSnapshotPropertyProgram.sha256
          == reviewedSystemdSnapshotPropertySha256;
        assert
          rootManagerManifest.bootPersistence.livePilot.systemdSnapshotPropertyTest.sha256
          == reviewedSystemdSnapshotPropertyTestSha256;
        assert rootManagerManifest.bootPersistence.livePilot.rollback.armedBeforeActivation;
        assert !rootManagerManifest.bootPersistence.livePilot.rollback.survivesHostReboot;
        assert rootManagerManifest.bootPersistence.livePilot.reboot.forbiddenDuringActivationWindow;
        assert !rootManagerManifest.bootPersistence.livePilot.reboot.performed;
        assert rootManagerManifest.bootPersistence.livePilot.hostCandidateRetentionPerformed;
        assert rootManagerManifest.bootPersistence.livePilot.hostRegistrationPerformed;
        assert rootManagerManifest.bootPersistence.livePilot.hostActivationPerformed;
        assert rootManagerManifest.bootPersistence.livePilot.hostBootLinkCreated;
        assert !rootManagerManifest.bootPersistence.livePilot.hostRebootPerformed;
        assert
          rootManagerManifest.bootPersistence.liveActivation.stateClass
          == "ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED";
        assert rootManagerManifest.bootPersistence.liveActivation.host == "sparkle-01";
        assert rootManagerManifest.bootPersistence.liveActivation.localConsoleConfirmed;
        assert rootManagerManifest.bootPersistence.liveActivation.rollbackDisarmed;
        assert !rootManagerManifest.bootPersistence.liveActivation.rollbackServiceRan;
        assert rootManagerManifest.bootPersistence.liveActivation.protectedServicesUnchanged;
        assert rootManagerManifest.bootPersistence.liveActivation.bootLinkCreated;
        assert rootManagerManifest.bootPersistence.liveActivation.managedPathCount == 6;
        assert rootManagerManifest.bootPersistence.liveActivation.managedServiceCount == 3;
        assert !rootManagerManifest.bootPersistence.liveActivation.hostRebootPerformed;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.status
          == "live-recovery-operational-host-not-armed";
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.transactionProgram.sha256
          == reviewedRootRebootRecoveryTransactionSha256;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.postbootAuditor.sha256
          == reviewedRootCanaryAuditSha256;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.productionBundle.outputPath
          == rootRebootRecoveryBundle.outPath;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.productionBundle.gcRoot
          == rootRebootRecoveryGcRoot;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.isolatedTransactionTest.result == "passed";
        assert rootManagerManifest.bootPersistence.rebootRecovery.isolatedTransactionTest.matchesCurrent;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.isolatedTransactionTest.subtestCount == 13;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.isolatedTransactionTest.disposableRestarts == 2;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.isolatedTransactionTest.provesAutomaticRollback;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.isolatedTransactionTest.provesConfirmedRetention;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.isolatedTransactionTest.provesExactCleanup;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.isolatedTransactionTest.provesSameBootDisarm;
        assert
          !rootManagerManifest.bootPersistence.rebootRecovery.isolatedTransactionTest.hostRecoveryArmed;
        assert
          !rootManagerManifest.bootPersistence.rebootRecovery.isolatedTransactionTest.hostRebootPerformed;
        assert !rootManagerManifest.bootPersistence.rebootRecovery.hostRecoveryArmed;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.livePilot.status
          == "repository-design-complete-host-not-armed";
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.livePilot.snapshotProgram.sha256
          == reviewedRootRebootRecoverySnapshotSha256;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.livePilot.pilotProgram.sha256
          == reviewedRootRebootRecoveryPilotSha256;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.livePilot.operatorProgram.sha256
          == reviewedRootRebootRecoveryOperatorSha256;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.livePilot.pilotProgram.actions == [
            "arm"
            "disarm-preboot"
            "status"
            "confirm"
            "verify-rolled-back"
            "cleanup-rolled-back"
          ];
        assert !rootManagerManifest.bootPersistence.rebootRecovery.livePilot.pilotProgram.performsReboot;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.livePilot.operatorProgram.actions == [
            "snapshot"
            "restore"
            "arm"
            "disarm-preboot"
            "status"
            "confirm"
            "verify-rolled-back"
            "cleanup-rolled-back"
          ];
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.livePilot.operatorProgram.invokesExactSnapshotCopyPostboot;
        assert !rootManagerManifest.bootPersistence.rebootRecovery.livePilot.operatorProgram.performsReboot;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.livePilot.nixDaemonPostbootPolicy.activeServiceAccepted;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.livePilot.nixDaemonPostbootPolicy.idleServiceWithActiveSocketAccepted;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.livePilot.nixDaemonPostbootPolicy.preservesStrictSameBootProcessContinuity;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.livePilot.armingConfirmation
          == "ARM PERSISTENT RECOVERY";
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.livePilot.prebootDisarmConfirmation
          == "DISARM PREBOOT RECOVERY";
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.livePilot.requiresSeparateRebootAuthorization;
        assert rootManagerManifest.bootPersistence.rebootRecovery.livePilot.hostSnapshotCreated;
        assert !rootManagerManifest.bootPersistence.rebootRecovery.livePilot.hostRecoveryArmed;
        assert rootManagerManifest.bootPersistence.rebootRecovery.livePilot.hostRebootPerformed;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.liveAttempt.status
          == "automatic-rollback-verified-cleaned";
        assert rootManagerManifest.bootPersistence.rebootRecovery.liveAttempt.host == "sparkle-01";
        assert rootManagerManifest.bootPersistence.rebootRecovery.liveAttempt.operatorRebootPerformed;
        assert !rootManagerManifest.bootPersistence.rebootRecovery.liveAttempt.confirmedBeforeDeadline;
        assert rootManagerManifest.bootPersistence.rebootRecovery.liveAttempt.automaticRollbackCompleted;
        assert rootManagerManifest.bootPersistence.rebootRecovery.liveAttempt.rollbackVerified;
        assert rootManagerManifest.bootPersistence.rebootRecovery.liveAttempt.cleanupCompleted;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.liveAttempt.currentHostState
          == "ACTIVE_REGISTERED_GENERATION_TWO_TRIPLE_RETAINED";
        assert rootManagerManifest.bootPersistence.rebootRecovery.liveAttempt.recoverySurface == "absent";
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.restoration.status
          == "generation-three-restored-after-verified-postflight";
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.restoration.program.sha256
          == reviewedRootRecoveryRestoreGenerationThreeSha256;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.restoration.consoleAcknowledgement
          == "press-enter-after-local-console-check";
        assert !rootManagerManifest.bootPersistence.rebootRecovery.restoration.exactPhraseRequired;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.restoration.automaticRetentionAfterPostflight;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.restoration.resumableWhileRollbackTimerActive;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.restoration.priorAttempt.snapshotStamp
          == "20260903T042141Z";
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.restoration.priorAttempt.generationThreeActivated;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.restoration.priorAttempt.automaticPostflightPassed;
        assert
          !rootManagerManifest.bootPersistence.rebootRecovery.restoration.priorAttempt.retentionConfirmationMatched;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.restoration.priorAttempt.automaticRollbackCompleted;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.restoration.priorAttempt.currentHostState
          == "ACTIVE_REGISTERED_GENERATION_TWO_TRIPLE_RETAINED";
        assert rootManagerManifest.bootPersistence.rebootRecovery.restoration.preservesAllThreePilotRoots;
        assert !rootManagerManifest.bootPersistence.rebootRecovery.restoration.performsReboot;
        assert rootManagerManifest.bootPersistence.rebootRecovery.restoration.hostRestorationPerformed;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.restoration.snapshotStamp == "20260903T083058Z";
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.restoration.repositoryCommit
          == "1a191e246cbfacbff9946887f7b2b594b4486ff3";
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.restoration.currentHostState
          == "ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED";
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.restoration.automaticPostflightPasses == 2;
        assert rootManagerManifest.bootPersistence.rebootRecovery.restoration.rollbackDisarmed;
        assert !rootManagerManifest.bootPersistence.rebootRecovery.restoration.rollbackServiceRan;
        assert
          rootManagerManifest.bootPersistence.rebootRecovery.restoration.evidence
          == "root/system-manager/validation/2026-09-03-restoration-host-attempt-2.md";
        assert !rootManagerManifest.bootPersistence.rebootRecovery.hostRecoveryArmed;
        assert rootManagerManifest.bootPersistence.rebootRecovery.hostRebootPerformed;
        assert !rootCanaryConfig.services.userborn.enable;
        assert !rootCanaryConfig.security.enableWrappers;
        assert !rootCanaryConfig.system-manager.linkCurrentSystem;
        assert rootCanaryConfig.systemd.targets.system-manager.wantedBy == [ ];
        assert !rootCanaryConfig.environment.etc."dgx-setup/canary".replaceExisting;
        assert !rootCanaryConfig.environment.etc."tmpfiles.d".enable;
        assert rootCanaryConfig.systemd.tmpfiles.rules == [ ];
        assert rootCanaryConfig.systemd.tmpfiles.settings == { };
        rootPkgs.runCommand "dgx-root-manager-policy" { } ''
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
          generation_two_units="$(
            readlink -f -- \
              ${rootCanaryRegistrationTestConfig.build.etc.staticEnv}/systemd/system
          )"
          generation_three_units="$(
            readlink -f -- \
              ${rootCanaryBootPersistenceConfig.build.etc.staticEnv}/systemd/system
          )"
          test "$(find "$generation_two_units" -mindepth 1 -maxdepth 2 -printf x | wc -c)" -eq 5
          test "$(find "$generation_three_units" -mindepth 1 -maxdepth 2 -printf x | wc -c)" -eq 7
          test ! -e "$generation_two_units/default.target.wants/system-manager.target"
          test ! -L "$generation_two_units/default.target.wants/system-manager.target"
          test -L "$generation_three_units/default.target.wants/system-manager.target"
          test "$(readlink -- "$generation_three_units/default.target.wants/system-manager.target")" = ../system-manager.target
          for unit in \
            dgx-setup-canary.service \
            sysinit-reactivation.target \
            system-manager.target \
            system-manager.target.wants/dgx-setup-canary.service; do
            test "$(readlink -f -- "$generation_two_units/$unit")" = \
              "$(readlink -f -- "$generation_three_units/$unit")"
          done
          cmp \
            ${rootCanaryRegistrationTestGeneration}/services/services.json \
            ${rootCanaryBootPersistenceGeneration}/services/services.json
          grep -Fvx 'boot-persistence-generation=3' \
            ${rootCanaryBootPersistenceConfig.build.etc.entries."dgx-setup/canary".source}/dgx-setup/canary \
            | cmp - \
              ${rootCanaryRegistrationTestConfig.build.etc.entries."dgx-setup/canary".source}/dgx-setup/canary
          touch "$out"
        '';

      rootCanaryContainerTest = system-manager.lib.containerTest.makeContainerTest {
        hostPkgs = rootPkgs;
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
        hostPkgs = rootPkgs;
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

      rootCanaryRegistrationTransactionContainerTest =
        import ./root/system-manager/registration-transaction-test.nix
          {
            pkgs = rootPkgs;
            inherit
              rootCanary
              rootRegistrationTransactionProgram
              system-manager
              ;
          };

      rootCanaryGenerationSwitchTransactionContainerTest =
        import ./root/system-manager/generation-switch-transaction-test.nix
          {
            pkgs = rootPkgs;
            inherit
              rootCanary
              rootCanaryRegistrationTestGeneration
              rootGenerationSwitchTransactionProgram
              rootRegistrationTransactionProgram
              system-manager
              ;
          };

      rootCanaryBootPersistenceTransactionContainerTest =
        import ./root/system-manager/boot-persistence-transaction-test.nix
          {
            pkgs = rootPkgs;
            inherit
              rootBootPersistenceTransactionProgram
              rootCanary
              rootCanaryBootPersistenceGeneration
              rootCanaryRegistrationTestGeneration
              rootGenerationSwitchTransactionProgram
              rootRegistrationTransactionProgram
              system-manager
              ;
          };

      rootCanaryRebootRecoveryTransactionContainerTest =
        import ./root/system-manager/reboot-recovery-transaction-test.nix
          {
            pkgs = rootPkgs;
            inherit
              rootBootPersistenceTransactionProgram
              rootCanaryAuditProgram
              rootCanary
              rootCanaryBootPersistenceGeneration
              rootCanaryRegistrationTestGeneration
              rootGenerationSwitchTransactionProgram
              rootRebootRecoveryBundle
              rootRebootRecoveryTestBundle
              rootRegistrationTransactionProgram
              system-manager
              ;
          };

      tailscaleUnitLifecycleContainerTest = import ./root/tailscale/unit-lifecycle-test.nix {
        pkgs = rootPkgs;
        inherit
          rootManagerOverlays
          rootCanary
          rootCanaryBootPersistenceGeneration
          rootCanaryRegistrationTestGeneration
          rootTailscaleMigrationTransactionProgram
          system-manager
          ;
      };

      desktopModeLifecycleContainerTest = import ./root/desktop/mode-lifecycle-test.nix {
        pkgs = rootPkgs;
        inherit
          rootManagerOverlays
          rootCanary
          system-manager
          ;
      };

      desktopHeadlessTransactionContainerTest = import ./root/desktop/headless-transaction-test.nix {
        pkgs = rootPkgs;
        inherit
          rootCanary
          rootDesktopModeTransactionProgram
          rootManagerOverlays
          system-manager
          ;
      };

      desktopSwitchLifecycleContainerTest = import ./root/desktop/switch-lifecycle-test.nix {
        pkgs = rootPkgs;
        inherit
          rootCanary
          rootDesktopModeTransactionProgram
          rootManagerOverlays
          system-manager
          ;
      };

      nixBootstrapTestFixture = rootPkgs.runCommand "dgx-nix-bootstrap-test-fixture" { } ''
        mkdir -p \
          "$out/bootstrap/nix" \
          "$out/fleet" \
          "$out/root/nix" \
          "$out/scripts" \
          "$out/test-bin"
        cp ${./bootstrap/nix/source.json} "$out/bootstrap/nix/source.json"
        cp ${./fleet/hosts.json} "$out/fleet/hosts.json"
        cp ${./root/nix/store-paths.nix} "$out/root/nix/store-paths.nix"
        cp ${./scripts/bootstrap-nix.sh} "$out/scripts/bootstrap-nix.sh"
        cp ${./scripts/dgx-setup} "$out/scripts/dgx-setup"
        cp ${./scripts/rollback-fresh-nix-bootstrap.sh} \
          "$out/scripts/rollback-fresh-nix-bootstrap.sh"
        cp ${./scripts/update-nix-installer.sh} \
          "$out/scripts/update-nix-installer.sh"
        chmod 0755 "$out/scripts/"*
        printf '%s\n' \
          '#!/bin/sh' \
          "printf '%s\\n' 'NVIDIA GB10, 580.173.02'" \
          >"$out/test-bin/nvidia-smi"
        chmod 0755 "$out/test-bin/nvidia-smi"
      '';

      nixBootstrapLifecycleContainerTest = system-manager.lib.containerTest.makeContainerTest {
        hostPkgs = rootPkgs;
        name = "dgx-nix-bootstrap-lifecycle";
        toplevel = rootCanary;
        extraPathsToRegister = [ nixBootstrapTestFixture ];
        testScript = ''
          start_all()
          machine.wait_for_unit("multi-user.target")

          repo = "/home/n0b0dy/Development/DGX-setup"
          installer = "/root/nix-installer-preseed"
          fixed_path = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

          with subtest("Prepare a committed declared-host fixture outside the Nix store"):
              machine.succeed("hostname sparkle-01")
              machine.succeed("useradd --create-home --shell /bin/bash n0b0dy")
              machine.succeed(f"install -d -o n0b0dy -g n0b0dy '{repo}'")
              machine.succeed(f"cp -a '${nixBootstrapTestFixture}/.' '{repo}/'")
              machine.succeed(f"chown -R n0b0dy:n0b0dy '{repo}'")
              machine.succeed(f"chmod -R u+w '{repo}'")
              machine.succeed(
                  "install -m 0755 '${nixBootstrapTestFixture}/test-bin/nvidia-smi' "
                  "/usr/local/bin/nvidia-smi"
              )
              machine.succeed(f"install -m 0755 /usr/local/bin/nix-installer '{installer}'")
              machine.succeed(
                  "/nix/var/nix/profiles/default/bin/nix "
                  "--extra-experimental-features nix-command copy "
                  "--to file:///root/dgx-nix-runtime-cache "
                  "'${nixRuntimeStorePaths.${system}}'"
              )
              machine.succeed(
                  "sha256sum /usr/local/bin/nix-installer | "
                  "grep -F '7e6e2f753144d7f19b16a9fce4b354cb0f46d1d47e6908bfb9186c89e0e0e649'"
              )
              machine.succeed(f"runuser -u n0b0dy -- git -C '{repo}' init -q")
              machine.succeed(f"runuser -u n0b0dy -- git -C '{repo}' add -A")
              machine.succeed(
                  f"runuser -u n0b0dy -- git -C '{repo}' "
                  "-c user.name='DGX Bootstrap Test' "
                  "-c user.email='bootstrap-test@invalid' "
                  "commit -qm 'bootstrap fixture'"
              )
              commit = machine.succeed(
                  f"runuser -u n0b0dy -- git -C '{repo}' rev-parse HEAD"
              ).strip()

          with subtest("Return the driver-provisioned container to a clean Nix boundary"):
              machine.succeed(
                  "/usr/local/bin/nix-installer uninstall --no-confirm /nix/receipt.json"
              )
              # The container driver bootstraps Nix before this test and is not
              # itself the transaction under test. Normalize only its exact,
              # rootfs-baseline-absent Nix links before exercising our clean-host
              # path. The later repository rollback receives no such cleanup.
              machine.succeed(
                  "rm -rf -- "
                  "/root/.nix-profile /root/.nix-defexpr /root/.nix-channels "
                  "/root/.local/state/nix /root/.cache/nix "
                  "/etc/profile.d/nix.sh /etc/tmpfiles.d/nix-daemon.conf "
                  "/etc/systemd/system/nix-daemon.service "
                  "/etc/systemd/system/nix-daemon.socket "
                  "/etc/systemd/system/multi-user.target.wants/nix-daemon.service "
                  "/etc/systemd/system/sockets.target.wants/nix-daemon.socket"
              )
              machine.succeed("systemctl daemon-reload")
              machine.fail("test -e /nix || test -L /nix")
              machine.fail("test -e /etc/nix || test -L /etc/nix")
              machine.fail("test -e /root/.nix-profile || test -L /root/.nix-profile")
              machine.fail("test -e /root/.nix-defexpr || test -L /root/.nix-defexpr")
              machine.fail("test -e /root/.nix-channels || test -L /root/.nix-channels")
              machine.fail("test -e /root/.local/state/nix || test -L /root/.local/state/nix")
              machine.fail("test -e /root/.cache/nix || test -L /root/.cache/nix")
              machine.fail("getent group nixbld")
              machine.succeed(
                  "for index in $(seq 1 32); do "
                  "! getent passwd nixbld$index >/dev/null || exit 1; done"
              )

          root_command = (
              f"env PATH='{fixed_path}' SUDO_USER=n0b0dy "
              "NIX_CONFIG=$'substituters = file:///root/dgx-nix-runtime-cache\\n"
              "require-sigs = false' "
              f"DGX_NIX_BOOTSTRAP_PRESEEDED_INSTALLER='{installer}' "
              f"'{repo}/scripts/bootstrap-nix.sh' sparkle-01 --root-install "
              f"'{commit}' n0b0dy"
          )

          with subtest("Injected failure remains protected by receipt-driven rollback"):
              failure = machine.fail(
                  "DGX_NIX_BOOTSTRAP_TEST_FAIL_AFTER_RUNTIME=1 " + root_command
              )
              assert "injected post-runtime failure" in failure, failure
              timer = machine.succeed(
                  "systemctl list-units --type=timer --all --plain --no-legend "
                  "'dgx-nix-bootstrap-rollback-*.timer' | awk 'NR == 1 { print $1 }'"
              ).strip()
              assert timer.endswith(".timer"), timer
              machine.succeed(f"systemctl is-active --quiet '{timer}'")
              machine.succeed(f"systemctl start '{timer.removesuffix('.timer')}.service'")
              machine.wait_until_succeeds(
                  "find /var/lib/dgx-setup/nix-bootstrap -name ROLLED_BACK -print -quit | grep -q ."
              )
              machine.succeed(f"systemctl stop '{timer}'")
              machine.fail("test -e /nix || test -L /nix")
              machine.fail("test -e /etc/nix || test -L /etc/nix")
              machine.fail("test -e /root/.nix-profile || test -L /root/.nix-profile")
              machine.fail("test -e /root/.nix-defexpr || test -L /root/.nix-defexpr")
              machine.fail("test -e /root/.nix-channels || test -L /root/.nix-channels")
              machine.fail("test -e /root/.local/state/nix || test -L /root/.local/state/nix")
              machine.fail("test -e /root/.cache/nix || test -L /root/.cache/nix")
              machine.fail("getent group nixbld")

          with subtest("Clean install reaches the exact desired runtime and disarms"):
              success = machine.succeed(root_command)
              assert "BOOTSTRAP_STATUS=INSTALLED" in success, success
              machine.succeed("test \"$(/nix/var/nix/profiles/default/bin/nix --version | awk '{print $NF}')\" = 2.35.2")
              machine.succeed(
                  "/nix/var/nix/profiles/default/bin/nix config show experimental-features "
                  "| tr ' ' '\\n' | grep -Fx nix-command"
              )
              machine.succeed(
                  "/nix/var/nix/profiles/default/bin/nix config show experimental-features "
                  "| tr ' ' '\\n' | grep -Fx flakes"
              )
              machine.fail(
                  "systemctl is-active --quiet 'dgx-nix-bootstrap-rollback-*.timer'"
              )

          with subtest("A second run adopts the exact installation without mutation"):
              before = machine.succeed(
                  "sha256sum /nix/nix-installer /nix/receipt.json /etc/nix/nix.conf; "
                  "readlink -f /nix/var/nix/profiles/default"
              )
              adopted = machine.succeed(
                  f"runuser -u n0b0dy -- env HOME=/home/n0b0dy PATH='{fixed_path}' "
                  f"'{repo}/scripts/dgx-setup' bootstrap sparkle-01"
              )
              assert "BOOTSTRAP_STATUS=ADOPTED" in adopted, adopted
              assert "PASS|nix_features|flakes were enabled by the original install plan" in adopted, adopted
              after = machine.succeed(
                  "sha256sum /nix/nix-installer /nix/receipt.json /etc/nix/nix.conf; "
                  "readlink -f /nix/var/nix/profiles/default"
              )
              assert after == before
        '';
      };

      systemdSnapshotPropertyRegressionCheck =
        rootPkgs.runCommand "dgx-systemd-snapshot-property-test" { }
          ''
            test_root="$TMPDIR/dgx-systemd-snapshot-property-test"
            mkdir -p "$test_root/scripts"
            cp ${systemdSnapshotPropertyProgram} "$test_root/scripts/systemd-snapshot-property.sh"
            cp ${systemdSnapshotPropertyTestProgram} "$test_root/scripts/test-systemd-snapshot-property.sh"
            chmod +x "$test_root/scripts/"*.sh
            patchShebangs "$test_root/scripts"
            "$test_root/scripts/test-systemd-snapshot-property.sh" >"$out"
          '';

      codexRelaxedDefaultsRegressionCheck = pkgs.runCommand "dgx-codex-relaxed-defaults-test" { } ''
        test_root="$TMPDIR/dgx-codex-relaxed-defaults-test"
        mkdir -p "$test_root/scripts"
        cp ${codexRelaxedDefaultsReconcilerProgram} "$test_root/scripts/reconcile-codex-relaxed-defaults.sh"
        cp ${codexRelaxedDefaultsTestProgram} "$test_root/scripts/test-reconcile-codex-relaxed-defaults.sh"
        chmod +x "$test_root/scripts/"*.sh
        patchShebangs "$test_root/scripts"
        "$test_root/scripts/test-reconcile-codex-relaxed-defaults.sh" >"$out"
      '';

      homeConfigurations = lib.mapAttrs' (
        hostName: hostSpec:
        let
          userSpec = hostSpec.users.armen;
        in
        lib.nameValuePair "${userSpec.unixName}@${hostName}" (mkHome {
          inherit hostName hostSpec;
          userName = userSpec.unixName;
          homeDirectory = userSpec.homeDirectory;
        })
      ) fleetHosts;
    in
    {
      inherit homeConfigurations;

      systemConfigs.sparkle-01 = rootCanary;

      packages.${system} = {
        chromium = chromiumPackage;
        codex-cli = codexPackage;
        devbox = devboxPackage;
        hyprland = hyprlandPackage;
        lmstudio = lmstudioPackage;
        root-system-canary = rootCanary;
        root-system-canary-generation-two = rootCanaryRegistrationTestGeneration;
        root-system-canary-generation-three-boot = rootCanaryBootPersistenceGeneration;
        root-system-tailscale-migration = rootTailscaleMigrationGeneration;
        root-system-desktop-headless = rootDesktopHeadlessGeneration;
        root-system-desktop-gnome = rootDesktopGnomeGeneration;
        root-desktop-switch-bundle = rootDesktopSwitchBundle;
        root-tailscale-migration-bundle = rootTailscaleMigrationBundle;
        root-reboot-recovery = rootRebootRecoveryBundle;
        tailscale = tailscalePackage;
        tailscaled-unit = tailscaleService.package;
        xdg-desktop-portal-hyprland = hyprlandPortalPackage;
        zed-editor = zedPackage;
      };

      checks.${system} = {
        chromium-package = chromiumPackage;
        chromium-policy = chromiumPolicyCheck;
        codex-cli-package = codexPackage;
        codex-cli-policy = codexPolicyCheck;
        codex-relaxed-defaults = codexRelaxedDefaultsRegressionCheck;
        devbox-package = devboxPackage;
        devbox-policy = devboxPolicyCheck;
        desktop-controller-policy = desktopControllerPolicyCheck;
        desktop-headless-transaction-container = desktopHeadlessTransactionContainerTest;
        desktop-mode-lifecycle-container = desktopModeLifecycleContainerTest;
        desktop-switch-lifecycle-container = desktopSwitchLifecycleContainerTest;
        home-sparkle-01 = sparkleHome.activationPackage;
        home-base = baseProfile.activationPackage;
        home-graphical = graphicalProfile.activationPackage;
        home-hyprland = hyprlandProfile.activationPackage;
        home-hyprland-with-portal = hyprlandPortalProfile.activationPackage;
        home-update-rollback-fixture = homeUpdateRollbackTestProfile.activationPackage;
        lmstudio-package = lmstudioPackage;
        lmstudio-policy = lmstudioPolicyCheck;
        nix-bootstrap-lifecycle-container = nixBootstrapLifecycleContainerTest;
        profile-policy = profilePolicyCheck;
        root-canary-container = rootCanaryContainerTest;
        root-canary-boot-persistence-transaction-container =
          rootCanaryBootPersistenceTransactionContainerTest;
        root-canary-generation-switch-transaction-container =
          rootCanaryGenerationSwitchTransactionContainerTest;
        root-canary-systemd-snapshot-property = systemdSnapshotPropertyRegressionCheck;
        root-canary-registration-container = rootCanaryRegistrationContainerTest;
        root-canary-registration-transaction-container = rootCanaryRegistrationTransactionContainerTest;
        root-canary-reboot-recovery-transaction-container =
          rootCanaryRebootRecoveryTransactionContainerTest;
        root-manager-policy = rootManagerPolicyCheck;
        root-system-canary = rootCanary;
        root-system-tailscale-migration = rootTailscaleMigrationGeneration;
        tailscale-package = tailscalePackage;
        tailscale-migration-shellcheck = tailscaleMigrationShellCheck;
        tailscale-policy = tailscalePolicyCheck;
        tailscale-unit-lifecycle-container = tailscaleUnitLifecycleContainerTest;
        tailscaled-unit = tailscaleService.package;
        zed-editor-package = zedPackage;
        zed-editor-policy = zedPolicyCheck;
      };

      lib.dgxProfileManifests.${system} = profileManifests;
      lib.dgxRootManagerManifest.${system} = rootManagerManifest;
      lib.dgxFleetManifest.${system} = fleetSpec // {
        nixBootstrap = nixBootstrapSpec;
      };

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
