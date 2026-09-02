{
  system-manager,
  pkgs,
  rootCanary,
  rootCanaryRegistrationTestGeneration,
  rootCanaryBootPersistenceGeneration,
  rootRegistrationTransactionProgram,
  rootGenerationSwitchTransactionProgram,
  rootBootPersistenceTransactionProgram,
  rootCanaryAuditProgram,
  rootRebootRecoveryBundle,
  rootRebootRecoveryTestBundle,
}:

system-manager.lib.containerTest.makeContainerTest {
  hostPkgs = pkgs;
  name = "dgx-root-canary-reboot-recovery-transaction";
  toplevel = rootCanary;
  extraPathsToRegister = [
    rootCanaryRegistrationTestGeneration
    rootCanaryBootPersistenceGeneration
    rootRegistrationTransactionProgram
    rootGenerationSwitchTransactionProgram
    rootBootPersistenceTransactionProgram
    rootCanaryAuditProgram
    rootRebootRecoveryBundle
    rootRebootRecoveryTestBundle
  ];
  testScript = ''
    import json

    start_all()
    machine.wait_for_unit("multi-user.target")

    generation_one = "${rootCanary}"
    generation_two = "${rootCanaryRegistrationTestGeneration}"
    generation_three = "${rootCanaryBootPersistenceGeneration}"
    first_registration = "${rootRegistrationTransactionProgram}"
    generation_switch = "${rootGenerationSwitchTransactionProgram}"
    boot_transaction = "${rootBootPersistenceTransactionProgram}"
    audit_program = "${rootCanaryAuditProgram}"
    audit_path = "${
      pkgs.lib.makeBinPath [
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnugrep
        pkgs.jq
      ]
    }:/usr/sbin:/usr/bin:/sbin:/bin"
    production_recovery = "${rootRebootRecoveryBundle}"
    test_recovery = "${rootRebootRecoveryTestBundle}"
    profile_dir = "/nix/var/nix/profiles/system-manager-profiles"
    profile_path = f"{profile_dir}/system-manager"
    generation_one_path = f"{profile_dir}/system-manager-1-link"
    generation_two_path = f"{profile_dir}/system-manager-2-link"
    generation_three_path = f"{profile_dir}/system-manager-3-link"
    gcroot_path = "/nix/var/nix/gcroots/system-manager-current"
    generation_one_root = (
        "/nix/var/nix/gcroots/dgx-setup-root-canary-pilot"
    )
    generation_two_root = (
        "/nix/var/nix/gcroots/"
        "dgx-setup-root-canary-generation-two-pilot"
    )
    generation_three_root = (
        "/nix/var/nix/gcroots/"
        "dgx-setup-root-canary-boot-persistence-pilot"
    )
    recovery_root = (
        "/nix/var/nix/gcroots/"
        "dgx-setup-root-canary-reboot-recovery-pilot"
    )
    recovery_service = "dgx-root-reboot-recovery.service"
    recovery_timer = "dgx-root-reboot-recovery.timer"
    recovery_service_path = f"/etc/systemd/system/{recovery_service}"
    recovery_timer_path = f"/etc/systemd/system/{recovery_timer}"
    recovery_wants_path = (
        "/etc/systemd/system/timers.target.wants/"
        f"{recovery_timer}"
    )
    recovery_state_dir = "/var/lib/dgx-setup/reboot-recovery"
    recovery_state = f"{recovery_state_dir}/state"
    boot_link = (
        "/etc/systemd/system/default.target.wants/system-manager.target"
    )
    protected_paths = [
        "/etc/nix/nix.conf",
        "/etc/passwd",
        "/etc/group",
        "/etc/shadow",
    ]

    def protected_snapshot() -> dict[str, str]:
        return {
            path: machine.succeed(
                f"if test -e '{path}'; then "
                f"sha256sum '{path}' | cut -d' ' -f1; "
                "else printf absent; fi"
            ).strip()
            for path in protected_paths
        }

    def assert_absent(path: str) -> None:
        machine.fail(f"test -e '{path}' || test -L '{path}'")

    def raw_link(path: str) -> str:
        return machine.succeed(f"readlink -- '{path}'").strip()

    def profile_entries() -> list[str]:
        return machine.succeed(
            f"find '{profile_dir}' -mindepth 1 -maxdepth 1 "
            "-printf '%f\\n' | sort"
        ).splitlines()

    def run_first(action: str, *, expect_success: bool = True) -> str:
        command = (
            "env NIX_USER_CONF_FILES=/dev/null "
            f"/bin/bash '{first_registration}' '{action}' '{generation_one}'"
        )
        return machine.succeed(command) if expect_success else machine.fail(command)

    def run_switch(action: str, *, expect_success: bool = True) -> str:
        command = (
            "env NIX_USER_CONF_FILES=/dev/null "
            f"/bin/bash '{generation_switch}' '{action}' "
            f"'{generation_one}' '{generation_two}'"
        )
        return machine.succeed(command) if expect_success else machine.fail(command)

    def run_boot(action: str, *, expect_success: bool = True) -> str:
        command = (
            "env NIX_USER_CONF_FILES=/dev/null "
            f"/bin/bash '{boot_transaction}' '{action}' "
            f"'{generation_one}' '{generation_two}' '{generation_three}'"
        )
        return machine.succeed(command) if expect_success else machine.fail(command)

    def run_postboot_audit(recovery_expectation: str = "absent") -> str:
        command = (
            f"env PATH='{audit_path}' NIX_USER_CONF_FILES=/dev/null "
            f"/bin/bash '{audit_program}' "
            f"'{generation_three}' registered-third-boot "
            f"'{generation_one}' '{generation_two}' "
            f"postboot '{recovery_expectation}'"
        )
        return machine.succeed(command).strip()

    def run_recovery(
        action: str,
        *,
        phrase: str | None = None,
        failure_stage: str | None = None,
        expect_success: bool = True,
    ) -> str:
        injection = ""
        if failure_stage is not None:
            injection = f"DGX_RECOVERY_TEST_FAIL_STAGE='{failure_stage}' "
        argument = "" if phrase is None else f" '{phrase}'"
        command = (
            f"env {injection}NIX_USER_CONF_FILES=/dev/null "
            f"'{test_recovery}/bin/dgx-root-reboot-recovery' "
            f"'{action}'{argument}"
        )
        return machine.succeed(command) if expect_success else machine.fail(command)

    def assert_recovery_absent() -> None:
        for path in [
            recovery_root,
            recovery_state_dir,
            recovery_service_path,
            recovery_timer_path,
            recovery_wants_path,
        ]:
            assert_absent(path)
        for unit in [recovery_service, recovery_timer]:
            load_state = machine.succeed(
                f"systemctl show '{unit}' -p LoadState --value || true"
            ).strip()
            assert load_state in ["", "not-found"], (unit, load_state)

    def assert_generation(generation: int, *, postboot: bool = False) -> None:
        assert raw_link(generation_one_root) == generation_one
        assert raw_link(generation_two_root) == generation_two
        assert raw_link(generation_three_root) == generation_three
        assert raw_link(generation_one_path) == generation_one
        assert raw_link(generation_two_path) == generation_two
        if generation == 2:
            run_boot("verify-before")
            assert profile_entries() == [
                "system-manager",
                "system-manager-1-link",
                "system-manager-2-link",
            ]
            assert raw_link(profile_path) == "system-manager-2-link"
            assert raw_link(gcroot_path) == generation_two
            assert_absent(generation_three_path)
            assert_absent(boot_link)
        else:
            if postboot:
                assert run_postboot_audit() == (
                    "ACTIVE_REGISTERED_GENERATION_THREE_"
                    "BOOT_LINKED_REBOOTED_RETAINED"
                )
            else:
                run_boot("verify-after")
            assert profile_entries() == [
                "system-manager",
                "system-manager-1-link",
                "system-manager-2-link",
                "system-manager-3-link",
            ]
            assert raw_link(profile_path) == "system-manager-3-link"
            assert raw_link(gcroot_path) == generation_three
            assert raw_link(generation_three_path) == generation_three
            machine.succeed(f"test -L '{boot_link}'")
        assert protected_snapshot() == protected_before

    def restart_container() -> None:
        machine.shutdown()
        machine.__dict__.pop("container_pid", None)
        machine.start()
        machine.wait_for_boot()
        machine.wait_for_unit("default.target")

    production_service = (
        f"{production_recovery}/lib/systemd/system/{recovery_service}"
    )
    production_timer = (
        f"{production_recovery}/lib/systemd/system/{recovery_timer}"
    )
    test_service = f"{test_recovery}/lib/systemd/system/{recovery_service}"
    test_timer = f"{test_recovery}/lib/systemd/system/{recovery_timer}"

    with subtest("Normalized recovery bundles differ only by timer delay"):
        machine.succeed(
            f"systemd-analyze verify '{production_service}' '{production_timer}'"
        )
        machine.succeed(f"systemd-analyze verify '{test_service}' '{test_timer}'")
        production_service_text = machine.succeed(f"cat '{production_service}'")
        test_service_text = machine.succeed(f"cat '{test_service}'")
        assert production_service_text.count(production_recovery) == 1
        assert test_service_text.count(test_recovery) == 1
        assert production_service_text.replace(
            production_recovery, "RECOVERY_BUNDLE"
        ) == test_service_text.replace(test_recovery, "RECOVERY_BUNDLE")
        production_timer_text = machine.succeed(f"cat '{production_timer}'")
        test_timer_text = machine.succeed(f"cat '{test_timer}'")
        assert production_timer_text.count("OnBootSec=10min") == 1
        assert test_timer_text.count("OnBootSec=30s") == 1
        assert production_timer_text.replace(
            "OnBootSec=10min", "OnBootSec=TEST"
        ) == test_timer_text.replace("OnBootSec=30s", "OnBootSec=TEST")

    protected_before = protected_snapshot()
    machine.succeed(f"ln -s -- '{generation_one}' '{generation_one_root}'")
    activation_logs = machine.succeed(f"'{generation_one}/bin/activate'")
    assert "ERROR" not in activation_logs, activation_logs
    run_first("apply-first")
    machine.succeed(f"ln -s -- '{generation_two}' '{generation_two_root}'")
    run_switch("apply-switch")
    machine.succeed(f"ln -s -- '{generation_three}' '{generation_three_root}'")
    run_boot("apply-boot")
    machine.wait_for_unit("system-manager.target")
    machine.wait_for_unit("dgx-setup-canary.service")
    assert_generation(3)
    assert_recovery_absent()

    with subtest("Foreign recovery root is preserved and refused"):
        machine.succeed(f"printf foreign > '{recovery_root}'")
        run_recovery("arm", expect_success=False)
        machine.succeed(f"grep -Fx foreign '{recovery_root}'")
        machine.succeed(f"unlink '{recovery_root}'")
        assert_recovery_absent()
        assert_generation(3)

    with subtest("Foreign state parent permissions are preserved and refused"):
        machine.succeed("install -d -m 0755 /var/lib/dgx-setup")
        run_recovery("arm", expect_success=False)
        machine.succeed(
            "test \"$(stat -c %u:%g:%a /var/lib/dgx-setup)\" = 0:0:755"
        )
        machine.succeed("rmdir /var/lib/dgx-setup")
        assert_recovery_absent()
        assert_generation(3)

    with subtest("Foreign unit collision is preserved and refused"):
        machine.succeed(f"printf foreign > '{recovery_service_path}'")
        run_recovery("arm", expect_success=False)
        machine.succeed(f"grep -Fx foreign '{recovery_service_path}'")
        machine.succeed(f"unlink '{recovery_service_path}'")
        assert_recovery_absent()
        assert_generation(3)

    for stage in ["after-root", "after-state", "after-units"]:
        with subtest(f"Injected {stage} failure removes only partial recovery state"):
            run_recovery("arm", failure_stage=stage, expect_success=False)
            assert_recovery_absent()
            assert_generation(3)

    with subtest("Arming enables but never starts recovery on the current boot"):
        run_recovery("arm")
        run_recovery("verify-armed-preboot")
        machine.succeed(f"systemctl is-enabled --quiet '{recovery_timer}'")
        machine.fail(f"systemctl is-active --quiet '{recovery_timer}'")
        machine.fail(f"systemctl is-active --quiet '{recovery_service}'")
        run_recovery("arm", expect_success=False)
        run_recovery(
            "confirm",
            phrase="KEEP REBOOTED GENERATION THREE",
            expect_success=False,
        )
        run_recovery("rollback", expect_success=False)
        run_recovery("verify-armed-preboot")
        assert_generation(3)

    with subtest("Next boot automatically rolls back when confirmation is absent"):
        restart_container()
        machine.wait_until_succeeds(
            f"grep -Fx 'status=rolled-back' '{recovery_state}'",
            timeout=75,
        )
        machine.wait_until_succeeds(
            f"test \"$(systemctl show '{recovery_service}' -p ActiveState --value)\" "
            "!= activating",
            timeout=30,
        )
        run_recovery("verify-rolled-back")
        assert_generation(2)
        machine.fail(f"systemctl is-enabled --quiet '{recovery_timer}'")

    with subtest("Exact cleanup removes rollback evidence after verification"):
        run_recovery(
            "cleanup-rolled-back",
            phrase="CLEAN ROLLED BACK REBOOT RECOVERY",
        )
        assert_recovery_absent()
        assert_generation(2)

    with subtest("A confirmed next boot retains generation three and disarms recovery"):
        run_boot("apply-boot")
        assert_generation(3)
        run_recovery("arm")
        run_recovery("verify-armed-preboot")
        restart_container()
        machine.wait_for_unit("system-manager.target")
        machine.wait_for_unit("dgx-setup-canary.service")
        machine.wait_for_unit(recovery_timer)
        run_recovery("verify-armed-postboot")
        run_recovery(
            "confirm",
            phrase="KEEP REBOOTED GENERATION THREE",
        )
        assert_recovery_absent()
        assert_generation(3, postboot=True)

    with subtest("Disposable cleanup restores empty unregistered manager state"):
        run_boot("rollback-boot")
        run_switch("rollback-switch")
        run_first("rollback-first")
        machine.succeed(f"'{generation_one}/bin/deactivate'")
        machine.succeed(f"unlink '{generation_three_root}'")
        machine.succeed(f"unlink '{generation_two_root}'")
        machine.succeed(f"unlink '{generation_one_root}'")
        assert_absent(profile_dir)
        assert_absent(gcroot_path)
        assert_absent(boot_link)
        assert_recovery_absent()
        state = json.loads(
            machine.succeed(
                "cat /var/lib/system-manager/state/system-manager-state.json"
            )
        )
        assert state == {
            "fileTree": {"files": [], "backedUpFiles": []},
            "services": {},
            "version": 0,
        }
        assert protected_snapshot() == protected_before
  '';
}
