{
  system-manager,
  pkgs,
  rootManagerOverlays,
  rootCanary,
  rootCanaryRegistrationTestGeneration,
  rootCanaryBootPersistenceGeneration,
  rootTailscaleMigrationTransactionProgram,
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
          tailscale-migration-generation=4
        '';
      }
    ];
  };

  testMigrationBundle = import ./migration-bundle.nix {
    inherit pkgs;
    transactionProgram = rootTailscaleMigrationTransactionProgram;
    generationOne = rootCanary;
    generationTwo = rootCanaryRegistrationTestGeneration;
    generationThree = rootCanaryBootPersistenceGeneration;
    generationFour = testGeneration;
    rollbackDelay = "12s";
    name = "dgx-tailscale-migration-test";
  };
in
system-manager.lib.containerTest.makeContainerTest {
  hostPkgs = pkgs;
  name = "dgx-tailscale-unit-lifecycle";
  toplevel = rootCanary;
  extraPathsToRegister = [
    rootCanaryBootPersistenceGeneration
    rootCanaryRegistrationTestGeneration
    rootTailscaleMigrationTransactionProgram
    testGeneration
    testMigrationBundle
    vendorDaemon
    vendorUnit
  ];
  testScript = ''
    import json

    start_all()
    machine.wait_for_unit("multi-user.target")

    generation_one = "${rootCanary}"
    generation_two = "${rootCanaryRegistrationTestGeneration}"
    generation_three = "${rootCanaryBootPersistenceGeneration}"
    generation_four = "${testGeneration}"
    transaction = "${rootTailscaleMigrationTransactionProgram}"
    state_path = "/var/lib/system-manager/state/system-manager-state.json"
    profile_dir = "/nix/var/nix/profiles/system-manager-profiles"
    profile_path = f"{profile_dir}/system-manager"
    gcroot_path = "/nix/var/nix/gcroots/system-manager-current"
    identity_path = "/var/lib/tailscale/tailscaled.state"
    vendor_unit_path = "/usr/lib/systemd/system/tailscaled.service"
    managed_unit_path = "/etc/systemd/system/tailscaled.service"
    vendor_wants_path = (
        "/etc/systemd/system/multi-user.target.wants/tailscaled.service"
    )
    managed_wants_path = (
        "/etc/systemd/system/system-manager.target.wants/tailscaled.service"
    )
    rollback_service = "dgx-tailscale-migration-rollback.service"
    rollback_timer = "dgx-tailscale-migration-rollback.timer"
    rollback_service_path = f"/etc/systemd/system/{rollback_service}"
    rollback_timer_path = f"/etc/systemd/system/{rollback_timer}"
    rollback_wants_path = (
        f"/etc/systemd/system/timers.target.wants/{rollback_timer}"
    )
    migration_state_dir = "/var/lib/dgx-setup/tailscale-migration"
    migration_armed = f"{migration_state_dir}/armed"
    migration_rolled_back = f"{migration_state_dir}/rolled-back"
    pilot_roots = {
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
    }

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

    def run_transaction(
        action: str,
        *,
        failure_stage: str | None = None,
        expect_success: bool = True,
    ) -> str:
        injection = ""
        if failure_stage is not None:
            injection = (
                "DGX_TAILSCALE_MIGRATION_TEST_FAIL_STAGE="
                f"'{failure_stage}' "
            )
        command = (
            "env NIX_USER_CONF_FILES=/dev/null "
            f"{injection}/bin/bash '{transaction}' '{action}' "
            f"'{generation_one}' '{generation_two}' "
            f"'{generation_three}' '{generation_four}'"
        )
        if expect_success:
            return machine.succeed(command)
        return machine.fail(command)

    def assert_profile(generation: int) -> None:
        candidate = generation_four if generation == 4 else generation_three
        expected_entries = [
            "system-manager",
            "system-manager-1-link",
            "system-manager-2-link",
            "system-manager-3-link",
        ]
        if generation == 4:
            expected_entries.append("system-manager-4-link")
        entries = machine.succeed(
            f"find '{profile_dir}' -mindepth 1 -maxdepth 1 "
            "-printf '%f\\n' | sort"
        ).splitlines()
        assert entries == expected_entries
        assert machine.succeed(f"readlink '{profile_path}'").strip() == (
            f"system-manager-{generation}-link"
        )
        assert machine.succeed(f"readlink -f '{profile_path}'").strip() == candidate
        assert machine.succeed(f"readlink '{gcroot_path}'").strip() == candidate

    def install_reboot_persistent_guard() -> None:
        machine.succeed(f"install -d -m 0700 '{migration_state_dir}'")
        machine.succeed(f"rm -f '{migration_rolled_back}'")
        machine.succeed(f"touch '{migration_armed}'")
        machine.succeed(
            f"ln -s '${testMigrationBundle}/lib/systemd/system/{rollback_service}' "
            f"'{rollback_service_path}'"
        )
        machine.succeed(
            f"ln -s '${testMigrationBundle}/lib/systemd/system/{rollback_timer}' "
            f"'{rollback_timer_path}'"
        )
        machine.succeed(
            "install -d -m 0755 /etc/systemd/system/timers.target.wants"
        )
        machine.succeed(
            f"ln -s '../{rollback_timer}' '{rollback_wants_path}'"
        )
        machine.succeed("systemctl daemon-reload")
        machine.succeed(f"systemctl start '{rollback_timer}'")
        machine.succeed(f"systemctl is-active --quiet '{rollback_timer}'")

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

        machine.succeed(f"install -d -m 0755 '{profile_dir}'")
        for index, candidate in enumerate(
            [generation_one, generation_two, generation_three],
            start=1,
        ):
            machine.succeed(
                f"ln -s '{candidate}' '{profile_dir}/system-manager-{index}-link'"
            )
        machine.succeed(
            f"ln -s system-manager-3-link '{profile_path}'"
        )
        machine.succeed(f"ln -s '{generation_three}' '{gcroot_path}'")
        for path, candidate in pilot_roots.items():
            machine.succeed(f"ln -s '{candidate}' '{path}'")

    with subtest("Generation three preserves the running vendor access plane"):
        logs = machine.succeed(f"'{generation_three}/bin/activate'")
        assert "ERROR" not in logs, logs
        machine.wait_for_unit("system-manager.target")
        machine.wait_for_unit("dgx-setup-canary.service")
        assert main_pid() == vendor_pid
        assert_vendor_running()
        assert_manager_state(generation=3)
        assert_profile(3)
        run_transaction("verify-before")

    with subtest("Injected registration failure rolls back without cutting access"):
        run_transaction(
            "apply",
            failure_stage="after-registration",
            expect_success=False,
        )
        assert_vendor_running()
        assert_manager_state(generation=3)
        assert_profile(3)

    with subtest("Generation four takes service ownership with one explicit restart"):
        logs = run_transaction("apply")
        assert "FAIL" not in logs, logs
        machine.succeed(f"test -L '{managed_unit_path}'")
        machine.succeed(f"test -L '{managed_wants_path}'")
        machine.succeed(f"test -L '{vendor_wants_path}'")
        machine.wait_for_unit("tailscaled.service")
        assert_candidate_running()
        assert_manager_state(generation=4)
        assert_profile(4)
        run_transaction("verify-after")

    with subtest("The Nix-owned service survives a container reboot"):
        restart_container()
        machine.wait_for_unit("system-manager.target")
        machine.wait_for_unit("dgx-setup-canary.service")
        machine.wait_for_unit("tailscaled.service")
        assert_candidate_running()
        assert_manager_state(generation=4)
        assert_profile(4)

    with subtest("Rollback removes Nix ownership and restores the vendor unit"):
        logs = run_transaction("rollback")
        assert "FAIL" not in logs, logs
        assert_absent(managed_unit_path)
        assert_absent(managed_wants_path)
        machine.succeed(f"test -L '{vendor_wants_path}'")
        machine.wait_for_unit("tailscaled.service")
        assert_vendor_running()
        assert_manager_state(generation=3)
        assert_profile(3)
        run_transaction("verify-before")

    with subtest("The restored vendor service survives another reboot"):
        restart_container()
        machine.wait_for_unit("system-manager.target")
        machine.wait_for_unit("dgx-setup-canary.service")
        machine.wait_for_unit("tailscaled.service")
        assert_vendor_running()
        assert_manager_state(generation=3)
        assert_profile(3)
        assert_absent(managed_unit_path)
        assert_absent(managed_wants_path)

    with subtest("Persistent guard rolls back after an unconfirmed candidate reboot"):
        install_reboot_persistent_guard()
        logs = machine.succeed(
            "'${testMigrationBundle}/bin/dgx-root-tailscale-migration' apply"
        )
        assert "FAIL" not in logs, logs
        assert_candidate_running()
        assert_profile(4)

        restart_container()
        machine.wait_until_succeeds(f"test -e '{migration_rolled_back}'")
        machine.wait_for_unit("tailscaled.service")
        assert_absent(migration_armed)
        assert_vendor_running()
        assert_manager_state(generation=3)
        assert_profile(3)
        assert_absent(managed_unit_path)
        assert_absent(managed_wants_path)
  '';
}
