{
  system-manager,
  pkgs,
  rootManagerOverlays,
  rootCanary,
  fleetRootBootstrapTransactionProgram,
}:

let
  fakeDaemon =
    provider:
    pkgs.writeShellScript "tailscaled-${provider}-fleet-fixture" ''
      set -eu
      if [ "''${1-}" = --cleanup ]; then exit 0; fi
      printf '%s\n' '${provider}' > /run/tailscale/provider
      ${pkgs.systemdMinimal}/bin/systemd-notify --ready
      exec ${pkgs.coreutils}/bin/sleep infinity
    '';

  vendorDaemon = fakeDaemon "vendor-apt";
  managedDaemon = fakeDaemon "nix-managed";
  managedTailscale = pkgs.runCommand "tailscale-fleet-fixture-1.102.3" { } ''
    mkdir -p "$out/bin"
    ln -s ${managedDaemon} "$out/bin/tailscaled"
  '';

  vendorUnit = pkgs.writeText "tailscaled-vendor-fleet-fixture.service" ''
    [Unit]
    Description=Tailscale node agent (disposable apt fixture)
    Wants=network-pre.target
    After=network-pre.target

    [Service]
    Type=notify
    ExecStart=/usr/sbin/tailscaled --state=/var/lib/tailscale/tailscaled.state
    ExecStopPost=/usr/sbin/tailscaled --cleanup
    Restart=on-failure
    RuntimeDirectory=tailscale
    StateDirectory=tailscale

    [Install]
    WantedBy=multi-user.target
  '';

  fakeGdm = pkgs.writeShellScript "gdm-fleet-fixture" ''
    set -eu
    printf '%s\n' factory-gnome > /run/dgx-fake-gdm
    ${pkgs.systemdMinimal}/bin/systemd-notify --ready
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';
  fakeGdmUnit = pkgs.writeText "gdm-fleet-fixture.service" ''
    [Unit]
    Description=Factory GDM fleet fixture

    [Service]
    Type=notify
    ExecStart=${fakeGdm}
    ExecStopPost=${pkgs.coreutils}/bin/rm -f /run/dgx-fake-gdm
  '';

  fakeDashboard = pkgs.writeShellScript "dashboard-fleet-fixture" ''
    set -eu
    printf '%s\n' factory-dashboard > /run/dgx-fake-dashboard
    ${pkgs.systemdMinimal}/bin/systemd-notify --ready
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';
  fakeDashboardUnit = pkgs.writeText "dashboard-fleet-fixture.service" ''
    [Unit]
    Description=Factory DGX Dashboard fleet fixture

    [Service]
    Type=notify
    ExecStart=${fakeDashboard}
    ExecStopPost=${pkgs.coreutils}/bin/rm -f /run/dgx-fake-dashboard

    [Install]
    WantedBy=default.target
  '';

  mkCandidate =
    {
      mode,
      tailscaleEnabled ? true,
    }:
    system-manager.lib.makeSystemConfig {
      overlays = rootManagerOverlays;
      specialArgs.dgxHostName = "sparkle-01";
      modules = [
        ../../modules/system/fleet-host.nix
        {
          dgx.root = {
            bootPersistence.enable = true;
            tailscale = {
              enable = tailscaleEnabled;
              package = if tailscaleEnabled then managedTailscale else null;
              sshDesired = tailscaleEnabled;
            };
            desktop = {
              enable = true;
              inherit mode;
            };
          };
          environment.etc."dgx-setup/canary".text = pkgs.lib.mkForce ''
            schema=1
            host=sparkle-01
            owner=DGX-setup
            purpose=declarative fleet root controller
            lifecycle=fresh-host
            tailscale-selected=${pkgs.lib.boolToString tailscaleEnabled}
            desktop-mode=${mode}
          '';
        }
      ];
    };

  factory = mkCandidate { mode = "gnome"; };
  headless = mkCandidate { mode = "headless"; };
  noTailscaleFactory = mkCandidate {
    mode = "gnome";
    tailscaleEnabled = false;
  };
  noTailscaleHeadless = mkCandidate {
    mode = "headless";
    tailscaleEnabled = false;
  };
  bundle = import ./bootstrap-bundle.nix {
    inherit pkgs;
    transactionProgram = fleetRootBootstrapTransactionProgram;
    factoryGeneration = factory;
    headlessGeneration = headless;
    rollbackDelay = "8s";
    name = "dgx-fleet-bootstrap-test";
  };
in
system-manager.lib.containerTest.makeContainerTest {
  hostPkgs = pkgs;
  name = "dgx-fleet-bootstrap-lifecycle";
  toplevel = rootCanary;
  extraPathsToRegister = [
    bundle
    factory
    fakeDashboard
    fakeDashboardUnit
    fakeGdm
    fakeGdmUnit
    fleetRootBootstrapTransactionProgram
    headless
    managedDaemon
    managedTailscale
    noTailscaleFactory
    noTailscaleHeadless
    vendorDaemon
    vendorUnit
  ];
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")

    factory = "${factory}"
    headless = "${headless}"
    bundle = "${bundle}"
    transaction = "${fleetRootBootstrapTransactionProgram}"
    no_tailscale_factory = "${noTailscaleFactory}"
    no_tailscale_headless = "${noTailscaleHeadless}"
    profile_dir = "/nix/var/nix/profiles/system-manager-profiles"
    profile = f"{profile_dir}/system-manager"
    upstream_root = "/nix/var/nix/gcroots/system-manager-current"
    factory_root = "/nix/var/nix/gcroots/dgx-setup-fleet-factory"
    headless_root = "/nix/var/nix/gcroots/dgx-setup-fleet-headless"
    state_dir = "/var/lib/dgx-setup/fleet-bootstrap"
    phase = f"{state_dir}/phase"
    armed = f"{state_dir}/armed"
    rolled_back = f"{state_dir}/rolled-back"
    rollback_service = "dgx-fleet-bootstrap-rollback.service"
    rollback_timer = "dgx-fleet-bootstrap-rollback.timer"
    rollback_service_path = f"/etc/systemd/system/{rollback_service}"
    rollback_timer_path = f"/etc/systemd/system/{rollback_timer}"
    rollback_wants = f"/etc/systemd/system/timers.target.wants/{rollback_timer}"
    bundle_root = "/nix/var/nix/gcroots/dgx-setup-fleet-bootstrap-rollback"

    def raw_link(path: str) -> str:
        return machine.succeed(f"readlink -- '{path}'").strip()

    def run_transaction(action: str, failure: str | None = None,
                        success: bool = True) -> str:
        injection = ""
        if failure:
            injection = f"DGX_FLEET_BOOTSTRAP_TEST_FAIL_STAGE='{failure}' "
        command = (
            "env NIX_USER_CONF_FILES=/dev/null " + injection
            + f"/bin/bash '{transaction}' '{action}' '{factory}' '{headless}'"
        )
        return machine.succeed(command) if success else machine.fail(command)

    def run_transaction_for(action: str, selected_factory: str,
                            selected_headless: str) -> str:
        return machine.succeed(
            "env NIX_USER_CONF_FILES=/dev/null "
            + f"/bin/bash '{transaction}' '{action}' "
            + f"'{selected_factory}' '{selected_headless}'"
        )

    def run_bundle(action: str) -> str:
        return machine.succeed(
            f"env NIX_USER_CONF_FILES=/dev/null "
            f"'{bundle}/bin/dgx-root-fleet-bootstrap' '{action}'"
        )

    def assert_vendor() -> None:
        machine.succeed("systemctl is-active --quiet tailscaled.service")
        machine.succeed("grep -Fx vendor-apt /run/tailscale/provider")
        machine.succeed(
            "test \"$(systemctl show tailscaled.service -p FragmentPath --value)\" "
            "= /usr/lib/systemd/system/tailscaled.service"
        )
        machine.succeed(
            "grep -Fx identity=disposable-fleet /var/lib/tailscale/tailscaled.state"
        )

    def assert_managed() -> None:
        machine.succeed("systemctl is-active --quiet tailscaled.service")
        machine.succeed("grep -Fx nix-managed /run/tailscale/provider")
        machine.succeed(
            "test \"$(systemctl show tailscaled.service -p FragmentPath --value)\" "
            "= /etc/systemd/system/tailscaled.service"
        )
        machine.succeed(
            "grep -Fx identity=disposable-fleet /var/lib/tailscale/tailscaled.state"
        )

    def assert_pristine() -> None:
        run_transaction("verify-pristine")
        machine.fail(f"test -e '{upstream_root}' || test -L '{upstream_root}'")
        machine.fail(f"test -e '{profile}' || test -L '{profile}'")
        assert_vendor()
        machine.succeed("systemctl is-active --quiet gdm.service")
        machine.succeed("systemctl is-active --quiet dgx-dashboard.service")

    def assert_factory() -> None:
        run_bundle("verify-factory")
        assert raw_link(profile) == "system-manager-1-link"
        assert raw_link(upstream_root) == factory
        assert_managed()
        machine.succeed("systemctl is-active --quiet gdm.service")
        machine.succeed("systemctl is-active --quiet dgx-dashboard.service")

    def assert_headless() -> None:
        run_bundle("verify-headless")
        assert raw_link(profile) == "system-manager-2-link"
        assert raw_link(upstream_root) == headless
        assert_managed()
        machine.fail("systemctl is-active --quiet gdm.service")
        machine.fail("systemctl is-active --quiet dgx-dashboard.service")

    def install_guard(selected_phase: str) -> None:
        machine.succeed(f"install -d -m 0700 '{state_dir}'")
        machine.succeed(f"printf '%s\\n' '{selected_phase}' > '{phase}'")
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
        machine.succeed("install -d /etc/systemd/system/timers.target.wants")
        machine.succeed(f"ln -s -- '../{rollback_timer}' '{rollback_wants}'")
        machine.succeed("systemctl daemon-reload")
        machine.succeed(f"systemctl start '{rollback_timer}'")
        machine.succeed(f"systemctl is-active --quiet '{rollback_timer}'")

    def cleanup_guard() -> None:
        machine.succeed(f"systemctl stop '{rollback_timer}' || true")
        machine.succeed(
            f"rm -f '{rollback_wants}' '{rollback_timer_path}' "
            f"'{rollback_service_path}' '{bundle_root}'"
        )
        machine.succeed(f"rm -rf '{state_dir}'")
        machine.succeed("systemctl daemon-reload")

    def restart_container() -> None:
        machine.shutdown()
        machine.__dict__.pop("container_pid", None)
        machine.start()
        machine.wait_for_boot()
        machine.wait_for_unit("default.target")

    with subtest("Install factory GNOME and apt-shaped Tailscale fixtures"):
        machine.succeed("hostname sparkle-01")
        machine.succeed("install -d /usr/lib/systemd/system /usr/sbin")
        machine.succeed("install -m 0755 '${vendorDaemon}' /usr/sbin/tailscaled")
        machine.succeed(
            "install -m 0644 '${vendorUnit}' /usr/lib/systemd/system/tailscaled.service"
        )
        machine.succeed(
            "install -m 0644 '${fakeGdmUnit}' /usr/lib/systemd/system/gdm.service"
        )
        machine.succeed("install -d /etc/systemd/system/default.target.wants")
        machine.succeed(
            "ln -s /usr/lib/systemd/system/gdm.service "
            "/etc/systemd/system/display-manager.service"
        )
        machine.succeed(
            "install -m 0644 '${fakeDashboardUnit}' "
            "/etc/systemd/system/dgx-dashboard.service"
        )
        machine.succeed(
            "ln -s ../dgx-dashboard.service "
            "/etc/systemd/system/default.target.wants/dgx-dashboard.service"
        )
        machine.succeed("install -d -m 0700 /var/lib/tailscale")
        machine.succeed(
            "printf 'identity=disposable-fleet\\n' > "
            "/var/lib/tailscale/tailscaled.state"
        )
        machine.succeed("chmod 0600 /var/lib/tailscale/tailscaled.state")
        machine.succeed("systemctl daemon-reload")
        machine.succeed("systemctl enable --now tailscaled.service")
        machine.succeed(
            "systemctl start graphical.target gdm.service dgx-dashboard.service"
        )
        machine.wait_for_unit("tailscaled.service")
        machine.wait_for_unit("gdm.service")
        machine.wait_for_unit("dgx-dashboard.service")
        machine.succeed(f"ln -s -- '{factory}' '{factory_root}'")
        machine.succeed(f"ln -s -- '{headless}' '{headless_root}'")
        assert_pristine()

    with subtest("Tailscale-disabled candidates leave the vendor access plane unowned"):
        machine.succeed(f"ln -sfn -- '{no_tailscale_factory}' '{factory_root}'")
        machine.succeed(f"ln -sfn -- '{no_tailscale_headless}' '{headless_root}'")
        run_transaction_for(
            "install-factory", no_tailscale_factory, no_tailscale_headless
        )
        assert_vendor()
        run_transaction_for(
            "install-headless", no_tailscale_factory, no_tailscale_headless
        )
        assert_vendor()
        run_transaction_for(
            "rollback-factory", no_tailscale_factory, no_tailscale_headless
        )
        run_transaction_for(
            "rollback-pristine", no_tailscale_factory, no_tailscale_headless
        )
        machine.succeed(f"ln -sfn -- '{factory}' '{factory_root}'")
        machine.succeed(f"ln -sfn -- '{headless}' '{headless_root}'")
        assert_pristine()

    with subtest("Factory registration failure returns to exact pristine state"):
        run_transaction(
            "install-factory", failure="factory-after-registration", success=False
        )
        assert_pristine()

    with subtest("Persistent unconfirmed first deployment rolls back after reboot"):
        install_guard("factory")
        run_bundle("install-factory-guarded")
        assert_factory()
        restart_container()
        machine.wait_until_succeeds(f"test -e '{rolled_back}'")
        assert_pristine()
        cleanup_guard()

    with subtest("Confirmed first deployment survives reboot"):
        install_guard("factory")
        run_bundle("install-factory-guarded")
        assert_factory()
        restart_container()
        assert_factory()
        machine.succeed(f"systemctl stop '{rollback_timer}'")
        cleanup_guard()
        assert_factory()

    with subtest("Headless failure returns to the managed factory boundary"):
        run_transaction(
            "install-headless", failure="headless-after-isolate", success=False
        )
        assert_factory()

    with subtest("Unconfirmed headless switch rolls back without changing access"):
        install_guard("headless")
        run_bundle("install-headless-guarded")
        assert_headless()
        machine.wait_until_succeeds(f"test -e '{rolled_back}'")
        assert_factory()
        cleanup_guard()

    with subtest("Confirmed headless state survives reboot"):
        install_guard("headless")
        run_bundle("install-headless-guarded")
        assert_headless()
        machine.succeed(f"systemctl stop '{rollback_timer}'")
        cleanup_guard()
        restart_container()
        assert_headless()
  '';
}
