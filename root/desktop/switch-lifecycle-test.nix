{
  system-manager,
  pkgs,
  rootManagerOverlays,
  rootCanary,
  rootDesktopModeTransactionProgram,
}:

let
  fakeTailscaled = pkgs.writeShellScript "tailscaled-desktop-switch-fixture" ''
    set -eu
    if [ "''${1-}" = --cleanup ]; then exit 0; fi
    printf '%s\n' nix-managed > /run/tailscale/provider
    ${pkgs.systemdMinimal}/bin/systemd-notify --ready
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';

  fakeTailscalePackage = pkgs.runCommand "tailscale-desktop-switch-fixture-1.102.3" { } ''
    mkdir -p "$out/bin"
    ln -s ${fakeTailscaled} "$out/bin/tailscaled"
  '';

  fakeGdm = pkgs.writeShellScript "gdm-desktop-switch-fixture" ''
    set -eu
    printf '%s\n' factory-gnome > /run/dgx-fake-gdm
    ${pkgs.systemdMinimal}/bin/systemd-notify --ready
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';

  fakeGdmUnit = pkgs.writeText "gdm-desktop-switch-fixture.service" ''
    [Unit]
    Description=Factory GDM desktop-switch fixture
    After=systemd-user-sessions.service

    [Service]
    Type=notify
    ExecStart=${fakeGdm}
    ExecStopPost=${pkgs.coreutils}/bin/rm -f /run/dgx-fake-gdm
  '';

  # The real user-facing DGX Dashboard is wanted by default.target. Model that
  # exact boundary so the test proves it stops with headless mode and restarts
  # with factory GNOME. The Dashboard admin daemon remains headless-safe.
  fakeDashboard = pkgs.writeShellScript "dgx-dashboard-desktop-switch-fixture" ''
    set -eu
    printf '%s\n' factory-dashboard > /run/dgx-fake-dashboard
    ${pkgs.systemdMinimal}/bin/systemd-notify --ready
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';

  fakeDashboardUnit = pkgs.writeText "dgx-dashboard-desktop-switch-fixture.service" ''
    [Unit]
    Description=Factory DGX Dashboard desktop-switch fixture

    [Service]
    Type=notify
    ExecStart=${fakeDashboard}
    ExecStopPost=${pkgs.coreutils}/bin/rm -f /run/dgx-fake-dashboard

    [Install]
    WantedBy=default.target
  '';

  mkTestGeneration =
    {
      generation,
      desktopMode ? null,
    }:
    system-manager.lib.makeSystemConfig {
      overlays = rootManagerOverlays;
      modules = [
        ../../hosts/sparkle-01/system.nix
        {
          dgx.root =
            pkgs.lib.optionalAttrs (generation >= 3) {
              bootPersistence.enable = true;
            }
            // pkgs.lib.optionalAttrs (generation >= 4) {
              tailscale = {
                enable = true;
                package = fakeTailscalePackage;
                sshDesired = true;
              };
            }
            // pkgs.lib.optionalAttrs (desktopMode != null) {
              desktop = {
                enable = true;
                mode = desktopMode;
              };
            };
          environment.etc."dgx-setup/canary".text = pkgs.lib.mkForce ''
            schema=1
            host=sparkle-01
            owner=DGX-setup
            purpose=system-manager activation and rollback canary
            ${pkgs.lib.optionalString (generation >= 2) "registration-test-generation=2\n"}${
              pkgs.lib.optionalString (generation >= 3) "boot-persistence-generation=3\n"
            }${pkgs.lib.optionalString (generation >= 4) "tailscale-migration-generation=4\n"}${
              pkgs.lib.optionalString (
                desktopMode != null
              ) "desktop-controller-generation=5\ndesktop-mode=${desktopMode}\n"
            }
          '';
        }
      ];
    };

  generationOne = mkTestGeneration { generation = 1; };
  generationTwo = mkTestGeneration { generation = 2; };
  generationThree = mkTestGeneration { generation = 3; };
  generationFour = mkTestGeneration { generation = 4; };
  headlessGeneration = mkTestGeneration {
    generation = 5;
    desktopMode = "headless";
  };

  testBundle = import ./switch-bundle.nix {
    inherit pkgs;
    transactionProgram = rootDesktopModeTransactionProgram;
    inherit
      generationOne
      generationTwo
      generationThree
      generationFour
      headlessGeneration
      ;
    rollbackDelay = "12s";
    name = "dgx-desktop-switch-test";
  };
in
system-manager.lib.containerTest.makeContainerTest {
  hostPkgs = pkgs;
  name = "dgx-desktop-switch-lifecycle";
  toplevel = rootCanary;
  extraPathsToRegister = [
    fakeGdm
    fakeGdmUnit
    fakeDashboard
    fakeDashboardUnit
    generationOne
    generationTwo
    generationThree
    generationFour
    headlessGeneration
    rootDesktopModeTransactionProgram
    testBundle
  ];
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")

    generation_one = "${generationOne}"
    generation_two = "${generationTwo}"
    generation_three = "${generationThree}"
    generation_four = "${generationFour}"
    headless = "${headlessGeneration}"
    bundle = "${testBundle}"
    profile_dir = "/nix/var/nix/profiles/system-manager-profiles"
    profile_path = f"{profile_dir}/system-manager"
    gcroot_path = "/nix/var/nix/gcroots/system-manager-current"
    headless_root = "/nix/var/nix/gcroots/dgx-setup-desktop-headless-pilot"
    bundle_root = "/nix/var/nix/gcroots/dgx-setup-desktop-switch-rollback"
    state_dir = "/var/lib/dgx-setup/desktop-switch"
    armed = f"{state_dir}/armed"
    headless_marker = f"{state_dir}/headless"
    rolled_back = f"{state_dir}/rolled-back"
    rollback_service = "dgx-desktop-switch-rollback.service"
    rollback_timer = "dgx-desktop-switch-rollback.timer"
    rollback_service_path = f"/etc/systemd/system/{rollback_service}"
    rollback_timer_path = f"/etc/systemd/system/{rollback_timer}"
    rollback_wants_path = (
        f"/etc/systemd/system/timers.target.wants/{rollback_timer}"
    )
    roots = {
        "/nix/var/nix/gcroots/dgx-setup-root-canary-pilot": generation_one,
        (
            "/nix/var/nix/gcroots/"
            "dgx-setup-root-canary-generation-two-pilot"
        ): generation_two,
        (
            "/nix/var/nix/gcroots/"
            "dgx-setup-root-canary-boot-persistence-pilot"
        ): generation_three,
        (
            "/nix/var/nix/gcroots/"
            "dgx-setup-tailscale-migration-pilot"
        ): generation_four,
        headless_root: headless,
    }

    def raw_link(path: str) -> str:
        return machine.succeed(f"readlink -- '{path}'").strip()

    def tailscale_pid() -> str:
        return machine.succeed(
            "systemctl show tailscaled.service -p MainPID --value"
        ).strip()

    def dashboard_pid() -> str:
        return machine.succeed(
            "systemctl show dgx-dashboard.service -p MainPID --value"
        ).strip()

    def run_bundle(action: str) -> str:
        return machine.succeed(
            f"env NIX_USER_CONF_FILES=/dev/null "
            f"'{bundle}/bin/dgx-root-desktop-switch' '{action}'"
        )

    def install_guard() -> None:
        machine.succeed(f"install -d -m 0700 '{state_dir}'")
        machine.succeed(f"rm -f '{headless_marker}' '{rolled_back}'")
        machine.succeed(f"touch '{armed}'")
        machine.succeed(f"ln -s -- '{bundle}' '{bundle_root}'")
        machine.succeed(
            f"ln -s -- '{bundle}/lib/systemd/system/{rollback_service}' "
            f"'{rollback_service_path}'"
        )
        machine.succeed(
            f"ln -s -- '{bundle}/lib/systemd/system/{rollback_timer}' "
            f"'{rollback_timer_path}'"
        )
        machine.succeed(
            "install -d -m 0755 /etc/systemd/system/timers.target.wants"
        )
        machine.succeed(
            f"ln -s -- '../{rollback_timer}' '{rollback_wants_path}'"
        )
        machine.succeed("systemctl daemon-reload")
        machine.succeed(f"systemctl start '{rollback_timer}'")
        machine.succeed(f"systemctl is-active --quiet '{rollback_timer}'")
        machine.succeed(f"systemctl is-enabled --quiet '{rollback_timer}'")

    def cleanup_guard() -> None:
        machine.succeed(f"systemctl stop '{rollback_timer}' || true")
        machine.succeed(
            f"rm -f '{rollback_wants_path}' '{rollback_timer_path}' "
            f"'{rollback_service_path}' '{bundle_root}'"
        )
        machine.succeed(f"rm -rf '{state_dir}'")
        machine.succeed("systemctl daemon-reload")

    def assert_factory() -> None:
        run_bundle("verify-factory")
        assert raw_link(profile_path) == "system-manager-4-link"
        assert raw_link(gcroot_path) == generation_four
        machine.succeed("systemctl is-active --quiet gdm.service")
        machine.succeed("systemctl is-active --quiet dgx-dashboard.service")
        machine.succeed("grep -Fx factory-gnome /run/dgx-fake-gdm")
        machine.succeed(
            "grep -Fx factory-dashboard /run/dgx-fake-dashboard"
        )
        machine.succeed("systemctl is-active --quiet tailscaled.service")

    def assert_headless() -> None:
        run_bundle("verify-headless")
        assert raw_link(profile_path) == "system-manager-5-link"
        assert raw_link(gcroot_path) == headless
        machine.fail("systemctl is-active --quiet dgx-dashboard.service")
        machine.fail("test -e /run/dgx-fake-gdm")
        machine.fail("test -e /run/dgx-fake-dashboard")
        machine.succeed("systemctl is-active --quiet tailscaled.service")

    def restart_container() -> None:
        machine.shutdown()
        machine.__dict__.pop("container_pid", None)
        machine.start()
        machine.wait_for_boot()
        machine.wait_for_unit("default.target")

    with subtest("Install exact generation four and factory-GDM fixture"):
        machine.succeed("install -d -m 0755 /usr/lib/systemd/system")
        machine.succeed(
            "install -m 0644 '${fakeGdmUnit}' "
            "/usr/lib/systemd/system/gdm.service"
        )
        machine.succeed("install -d -m 0755 /etc/systemd/system")
        machine.succeed(
            "ln -s /usr/lib/systemd/system/gdm.service "
            "/etc/systemd/system/display-manager.service"
        )
        machine.succeed(
            "install -m 0644 '${fakeDashboardUnit}' "
            "/etc/systemd/system/dgx-dashboard.service"
        )
        machine.succeed(
            "install -d -m 0755 /etc/systemd/system/default.target.wants"
        )
        machine.succeed(
            "ln -s ../dgx-dashboard.service "
            "/etc/systemd/system/default.target.wants/dgx-dashboard.service"
        )
        machine.succeed("systemctl daemon-reload")
        for root, candidate in roots.items():
            machine.succeed(f"ln -s -- '{candidate}' '{root}'")
        logs = machine.succeed(f"'{generation_one}/bin/activate'")
        assert "ERROR" not in logs, logs
        for candidate in [
            generation_one,
            generation_two,
            generation_three,
            generation_four,
        ]:
            machine.succeed(f"'{candidate}/bin/register-profile'")
        logs = machine.succeed(f"'{generation_four}/bin/activate'")
        assert "ERROR" not in logs, logs
        machine.succeed(
            "systemctl start graphical.target gdm.service dgx-dashboard.service"
        )
        machine.wait_for_unit("tailscaled.service")
        machine.wait_for_unit("gdm.service")
        machine.wait_for_unit("dgx-dashboard.service")
        original_tailscale_pid = tailscale_pid()
        original_dashboard_pid = dashboard_pid()
        assert_factory()

    with subtest("Rollback units are valid and isolation-resistant"):
        machine.succeed(
            f"systemd-analyze verify "
            f"'{bundle}/lib/systemd/system/{rollback_service}' "
            f"'{bundle}/lib/systemd/system/{rollback_timer}'"
        )
        machine.succeed(
            f"grep -Fx 'IgnoreOnIsolate=yes' "
            f"'{bundle}/lib/systemd/system/{rollback_service}'"
        )
        machine.succeed(
            f"grep -Fx 'IgnoreOnIsolate=yes' "
            f"'{bundle}/lib/systemd/system/{rollback_timer}'"
        )

    with subtest("Unconfirmed same-boot headless switch rolls back automatically"):
        install_guard()
        run_bundle("apply-guarded")
        machine.succeed(f"test -e '{headless_marker}'")
        machine.succeed(f"systemctl is-active --quiet '{rollback_timer}'")
        assert_headless()
        assert tailscale_pid() == original_tailscale_pid
        machine.wait_until_succeeds(f"test -e '{rolled_back}'")
        machine.fail(f"test -e '{armed}'")
        assert_factory()
        assert dashboard_pid() != original_dashboard_pid
        assert tailscale_pid() == original_tailscale_pid
        cleanup_guard()

    with subtest("Confirmed headless switch stays after guard cleanup"):
        install_guard()
        run_bundle("apply-guarded")
        machine.succeed(f"test -e '{headless_marker}'")
        assert_headless()
        machine.succeed(f"systemctl stop '{rollback_timer}'")
        cleanup_guard()
        assert_headless()
        assert tailscale_pid() == original_tailscale_pid

    with subtest("Exact factory rollback prepares the reboot guard case"):
        run_bundle("rollback-factory")
        assert_factory()
        assert tailscale_pid() == original_tailscale_pid

    with subtest("Persistent guard survives reboot and restores factory GNOME"):
        install_guard()
        run_bundle("apply-guarded")
        assert_headless()
        machine.succeed(f"systemctl is-active --quiet '{rollback_timer}'")
        restart_container()
        machine.wait_until_succeeds(f"test -e '{rolled_back}'")
        machine.wait_for_unit("gdm.service")
        assert_factory()
        machine.fail(f"test -e '{armed}'")
        cleanup_guard()

    with subtest("All candidate roots and access state remain exact"):
        for root, candidate in roots.items():
            assert raw_link(root) == candidate
        machine.succeed("grep -Fx nix-managed /run/tailscale/provider")
        machine.succeed("systemctl is-active --quiet tailscaled.service")
  '';
}
