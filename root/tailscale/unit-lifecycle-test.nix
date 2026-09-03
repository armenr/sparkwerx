{
  system-manager,
  pkgs,
  rootManagerOverlays,
  rootCanary,
  rootCanaryBootPersistenceGeneration,
}:

let
  mkFakeDaemon =
    name: provider:
    pkgs.writeShellScript name ''
      set -eu

      if [ "''${1-}" = --cleanup ]; then
        exit 0
      fi

      printf '%s\n' '${provider}' > /run/tailscale/provider
      ${pkgs.systemdMinimal}/bin/systemd-notify --ready
      exec ${pkgs.coreutils}/bin/sleep infinity
    '';

  vendorDaemon = mkFakeDaemon "tailscaled-vendor-fixture" "vendor-apt";
  candidateDaemon = mkFakeDaemon "tailscaled-nix-fixture" "nix-candidate";

  candidatePackage = pkgs.runCommand "tailscale-test-candidate-1.102.3" { } ''
    mkdir -p "$out/bin"
    ln -s ${candidateDaemon} "$out/bin/tailscaled"
  '';

  vendorUnit = pkgs.writeText "tailscaled-vendor-fixture.service" ''
    [Unit]
    Description=Tailscale node agent (disposable apt fixture)
    Wants=network-pre.target
    After=network-pre.target NetworkManager.service systemd-resolved.service

    [Service]
    EnvironmentFile=/etc/default/tailscaled
    ExecStart=/usr/sbin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock --port=''${PORT} $FLAGS
    ExecStopPost=/usr/sbin/tailscaled --cleanup
    Restart=on-failure
    RuntimeDirectory=tailscale
    RuntimeDirectoryMode=0755
    StateDirectory=tailscale
    StateDirectoryMode=0700
    CacheDirectory=tailscale
    CacheDirectoryMode=0750
    Type=notify

    [Install]
    WantedBy=multi-user.target
  '';

  testGeneration = system-manager.lib.makeSystemConfig {
    overlays = rootManagerOverlays;
    modules = [
      ../../hosts/sparkle-01/system.nix
      {
        dgx.root = {
          bootPersistence.enable = true;
          tailscale = {
            enable = true;
            package = candidatePackage;
            sshDesired = true;
          };
        };
        environment.etc."dgx-setup/canary".text = pkgs.lib.mkForce ''
          schema=1
          host=sparkle-01
          owner=DGX-setup
          purpose=system-manager activation and rollback canary
          registration-test-generation=2
          boot-persistence-generation=3
          tailscale-migration-generation=4-test
        '';
      }
    ];
  };
in
system-manager.lib.containerTest.makeContainerTest {
  hostPkgs = pkgs;
  name = "dgx-tailscale-unit-lifecycle";
  toplevel = rootCanary;
  extraPathsToRegister = [
    rootCanaryBootPersistenceGeneration
    testGeneration
    vendorDaemon
    vendorUnit
  ];
  testScript = ''
    import json

    start_all()
    machine.wait_for_unit("multi-user.target")

    generation_three = "${rootCanaryBootPersistenceGeneration}"
    generation_four = "${testGeneration}"
    state_path = "/var/lib/system-manager/state/system-manager-state.json"
    identity_path = "/var/lib/tailscale/tailscaled.state"
    vendor_unit_path = "/usr/lib/systemd/system/tailscaled.service"
    managed_unit_path = "/etc/systemd/system/tailscaled.service"
    vendor_wants_path = (
        "/etc/systemd/system/multi-user.target.wants/tailscaled.service"
    )
    managed_wants_path = (
        "/etc/systemd/system/system-manager.target.wants/tailscaled.service"
    )

    generation_three_paths = {
        "/etc/dgx-setup/canary",
        "/etc/systemd/system/default.target.wants/system-manager.target",
        "/etc/systemd/system/dgx-setup-canary.service",
        "/etc/systemd/system/sysinit-reactivation.target",
        "/etc/systemd/system/system-manager.target",
        (
            "/etc/systemd/system/system-manager.target.wants/"
            "dgx-setup-canary.service"
        ),
    }
    generation_four_paths = generation_three_paths | {
        managed_unit_path,
        managed_wants_path,
    }
    generation_three_units = {
        "dgx-setup-canary.service",
        "sysinit-reactivation.target",
        "system-manager.target",
    }
    generation_four_units = generation_three_units | {"tailscaled.service"}

    def assert_absent(path: str) -> None:
        machine.fail(f"test -e '{path}' || test -L '{path}'")

    def property_value(unit: str, prop: str) -> str:
        return machine.succeed(
            f"systemctl show '{unit}' -p '{prop}' --value"
        ).strip()

    def main_pid() -> str:
        return property_value("tailscaled.service", "MainPID")

    def assert_identity() -> None:
        machine.succeed(f"grep -Fx 'identity=disposable-fixture' '{identity_path}'")
        machine.succeed(f"test \"$(stat -c %a '{identity_path}')\" = 600")

    def assert_manager_state(*, generation: int) -> None:
        state = json.loads(machine.succeed(f"cat '{state_path}'"))
        expected_paths = (
            generation_four_paths if generation == 4 else generation_three_paths
        )
        expected_units = (
            generation_four_units if generation == 4 else generation_three_units
        )
        assert state["version"] == 1
        assert set(state["fileTree"]["files"]) == expected_paths
        assert state["fileTree"]["backedUpFiles"] == []
        assert set(state["services"].keys()) == expected_units

    def assert_vendor_running() -> None:
        machine.succeed("systemctl is-active --quiet tailscaled.service")
        assert property_value("tailscaled.service", "FragmentPath") == vendor_unit_path
        machine.succeed("grep -Fx vendor-apt /run/tailscale/provider")
        assert_identity()

    def assert_candidate_running() -> None:
        machine.succeed("systemctl is-active --quiet tailscaled.service")
        assert property_value("tailscaled.service", "FragmentPath") == managed_unit_path
        machine.succeed("grep -Fx nix-candidate /run/tailscale/provider")
        assert_identity()

    def restart_container() -> None:
        machine.shutdown()
        machine.__dict__.pop("container_pid", None)
        machine.start()
        machine.wait_for_boot()
        machine.wait_for_unit("default.target")

    with subtest("Install and start an apt-shaped vendor service fixture"):
        machine.succeed("install -d -m 0755 /usr/lib/systemd/system /etc/default")
        machine.succeed(
            "install -m 0755 '${vendorDaemon}' /usr/sbin/tailscaled"
        )
        machine.succeed(
            "install -m 0644 '${vendorUnit}' "
            f"'{vendor_unit_path}'"
        )
        machine.succeed(
            "printf 'PORT=41641\\nFLAGS=\\n' > /etc/default/tailscaled"
        )
        machine.succeed("install -d -m 0700 /var/lib/tailscale")
        machine.succeed(
            f"printf 'identity=disposable-fixture\\n' > '{identity_path}'"
        )
        machine.succeed(f"chmod 0600 '{identity_path}'")
        machine.succeed("systemctl daemon-reload")
        machine.succeed("systemctl enable --now tailscaled.service")
        machine.wait_for_unit("tailscaled.service")
        machine.succeed(f"test -L '{vendor_wants_path}'")
        assert_absent(managed_unit_path)
        assert_absent(managed_wants_path)
        assert_vendor_running()
        vendor_pid = main_pid()

    with subtest("Generation three preserves the running vendor access plane"):
        logs = machine.succeed(f"'{generation_three}/bin/activate'")
        assert "ERROR" not in logs, logs
        machine.wait_for_unit("system-manager.target")
        machine.wait_for_unit("dgx-setup-canary.service")
        assert main_pid() == vendor_pid
        assert_vendor_running()
        assert_manager_state(generation=3)

    with subtest("Generation four takes service ownership with one explicit restart"):
        logs = machine.succeed(f"'{generation_four}/bin/activate'")
        assert "ERROR" not in logs, logs
        machine.succeed(f"test -L '{managed_unit_path}'")
        machine.succeed(f"test -L '{managed_wants_path}'")
        machine.succeed(f"test -L '{vendor_wants_path}'")
        machine.succeed("systemctl restart tailscaled.service")
        machine.wait_for_unit("tailscaled.service")
        assert_candidate_running()
        assert_manager_state(generation=4)

    with subtest("The Nix-owned service survives a container reboot"):
        restart_container()
        machine.wait_for_unit("system-manager.target")
        machine.wait_for_unit("dgx-setup-canary.service")
        machine.wait_for_unit("tailscaled.service")
        assert_candidate_running()
        assert_manager_state(generation=4)

    with subtest("Rollback removes Nix ownership and restores the vendor unit"):
        logs = machine.succeed(f"'{generation_three}/bin/activate'")
        assert "ERROR" not in logs, logs
        machine.fail("systemctl is-active --quiet tailscaled.service")
        assert_absent(managed_unit_path)
        assert_absent(managed_wants_path)
        machine.succeed(f"test -L '{vendor_wants_path}'")
        machine.succeed("systemctl start tailscaled.service")
        machine.wait_for_unit("tailscaled.service")
        assert_vendor_running()
        assert_manager_state(generation=3)

    with subtest("The restored vendor service survives another reboot"):
        restart_container()
        machine.wait_for_unit("system-manager.target")
        machine.wait_for_unit("dgx-setup-canary.service")
        machine.wait_for_unit("tailscaled.service")
        assert_vendor_running()
        assert_manager_state(generation=3)
        assert_absent(managed_unit_path)
        assert_absent(managed_wants_path)
  '';
}
