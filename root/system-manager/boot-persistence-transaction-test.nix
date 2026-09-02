{
  system-manager,
  pkgs,
  rootCanary,
  rootCanaryRegistrationTestGeneration,
  rootCanaryBootPersistenceGeneration,
  rootRegistrationTransactionProgram,
  rootGenerationSwitchTransactionProgram,
  rootBootPersistenceTransactionProgram,
}:

system-manager.lib.containerTest.makeContainerTest {
  hostPkgs = pkgs;
  name = "dgx-root-canary-boot-persistence-transaction";
  toplevel = rootCanary;
  extraPathsToRegister = [
    rootCanaryRegistrationTestGeneration
    rootCanaryBootPersistenceGeneration
    rootRegistrationTransactionProgram
    rootGenerationSwitchTransactionProgram
    rootBootPersistenceTransactionProgram
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
    state_path = "/var/lib/system-manager/state/system-manager-state.json"
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
    boot_link = (
        "/etc/systemd/system/default.target.wants/system-manager.target"
    )
    unmanaged_tmpfiles_sentinel = "/run/dgx-unmanaged-tmpfiles-sentinel"

    managed_common_paths = [
        "/etc/dgx-setup/canary",
        "/etc/systemd/system/dgx-setup-canary.service",
        "/etc/systemd/system/sysinit-reactivation.target",
        "/etc/systemd/system/system-manager.target",
        (
            "/etc/systemd/system/system-manager.target.wants/"
            "dgx-setup-canary.service"
        ),
    ]
    forbidden_paths = [
        "/etc/profile.d/system-manager-path.sh",
        "/etc/environment.d/10-system-manager.conf",
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
    managed_units = [
        "dgx-setup-canary.service",
        "sysinit-reactivation.target",
        "system-manager.target",
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

    def resolved(path: str) -> str:
        return machine.succeed(f"readlink -f -- '{path}'").strip()

    def profile_entries() -> list[str]:
        return machine.succeed(
            f"find '{profile_dir}' -mindepth 1 -maxdepth 1 "
            "-printf '%f\\n' | sort"
        ).splitlines()

    def expected_live_links(
        candidate: str,
        *,
        boot_enabled: bool,
    ) -> dict[str, str]:
        etc_map = json.loads(
            machine.succeed(f"cat '{candidate}/etcFiles/etcFiles.json'")
        )
        service_map = json.loads(
            machine.succeed(f"cat '{candidate}/services/services.json'")
        )
        canary_source = etc_map["entries"]["dgx-setup/canary"]["source"]
        service_source = service_map["dgx-setup-canary.service"]["storePath"]
        manager_source = service_map["system-manager.target"]["storePath"]
        links = {
            "/etc/dgx-setup/canary": resolved(
                f"{canary_source}/dgx-setup/canary"
            ),
            "/etc/systemd/system/dgx-setup-canary.service": resolved(
                service_source
            ),
            "/etc/systemd/system/sysinit-reactivation.target": resolved(
                service_map["sysinit-reactivation.target"]["storePath"]
            ),
            "/etc/systemd/system/system-manager.target": resolved(
                manager_source
            ),
            (
                "/etc/systemd/system/system-manager.target.wants/"
                "dgx-setup-canary.service"
            ): resolved(service_source),
        }
        if boot_enabled:
            links[boot_link] = resolved(manager_source)
        return links

    def run_first(action: str, *, expect_success: bool = True) -> str:
        command = (
            "env NIX_USER_CONF_FILES=/dev/null "
            f"/bin/bash '{first_registration}' '{action}' '{generation_one}'"
        )
        if expect_success:
            return machine.succeed(command)
        return machine.fail(command)

    def run_switch(action: str, *, expect_success: bool = True) -> str:
        command = (
            "env NIX_USER_CONF_FILES=/dev/null "
            f"/bin/bash '{generation_switch}' '{action}' "
            f"'{generation_one}' '{generation_two}'"
        )
        if expect_success:
            return machine.succeed(command)
        return machine.fail(command)

    def run_boot(
        action: str,
        *,
        failure_stage: str | None = None,
        expect_success: bool = True,
    ) -> str:
        injection = ""
        if failure_stage is not None:
            injection = (
                "DGX_BOOT_PERSISTENCE_TEST_FAIL_STAGE="
                f"'{failure_stage}' "
            )
        command = (
            "env NIX_USER_CONF_FILES=/dev/null "
            f"{injection}/bin/bash '{boot_transaction}' '{action}' "
            f"'{generation_one}' '{generation_two}' '{generation_three}'"
        )
        if expect_success:
            return machine.succeed(command)
        return machine.fail(command)

    def assert_bounded_files(generation: int) -> None:
        candidate = generation_three if generation == 3 else generation_two
        boot_enabled = generation == 3
        expected_paths = managed_common_paths.copy()
        if boot_enabled:
            expected_paths.append(boot_link)
        state = json.loads(machine.succeed(f"cat '{state_path}'"))
        assert state["version"] == 1
        assert set(state["fileTree"]["files"]) == set(expected_paths)
        assert state["fileTree"]["backedUpFiles"] == []
        assert set(state["services"].keys()) == set(managed_units)
        machine.succeed("grep -Fx 'host=sparkle-01' /etc/dgx-setup/canary")
        machine.succeed(
            "grep -Fx 'registration-test-generation=2' "
            "/etc/dgx-setup/canary"
        )
        boot_marker = (
            "grep -Fx 'boot-persistence-generation=3' "
            "/etc/dgx-setup/canary"
        )
        if boot_enabled:
            machine.succeed(boot_marker)
        else:
            machine.fail(boot_marker)
        observed_links = {}
        for path in expected_paths:
            machine.succeed(f"test -L '{path}'")
            observed_links[path] = resolved(path)
        assert observed_links == expected_live_links(
            candidate,
            boot_enabled=boot_enabled,
        )
        if not boot_enabled:
            assert_absent(boot_link)
        for path in forbidden_paths:
            assert_absent(path)
        assert_absent(unmanaged_tmpfiles_sentinel)
        assert protected_snapshot() == protected_before

    def assert_units_after_activation() -> None:
        for unit in managed_units:
            machine.succeed(
                f"test \"$(systemctl show '{unit}' -p ActiveState --value)\" "
                "= active"
            )
            machine.succeed(
                f"test \"$(systemctl show '{unit}' -p NeedDaemonReload --value)\" "
                "= no"
            )

    def assert_registration(generation: int) -> None:
        if generation == 2:
            assert profile_entries() == [
                "system-manager",
                "system-manager-1-link",
                "system-manager-2-link",
            ]
            assert raw_link(profile_path) == "system-manager-2-link"
            assert raw_link(gcroot_path) == generation_two
            assert_absent(generation_three_path)
            candidate = generation_two
        else:
            assert profile_entries() == [
                "system-manager",
                "system-manager-1-link",
                "system-manager-2-link",
                "system-manager-3-link",
            ]
            assert raw_link(profile_path) == "system-manager-3-link"
            assert raw_link(gcroot_path) == generation_three
            assert raw_link(generation_three_path) == generation_three
            candidate = generation_three
        assert raw_link(generation_one_path) == generation_one
        assert raw_link(generation_two_path) == generation_two
        assert raw_link(generation_one_root) == generation_one
        assert raw_link(generation_two_root) == generation_two
        assert raw_link(generation_three_root) == generation_three
        assert resolved(profile_path) == candidate

    def assert_generation(generation: int) -> None:
        assert_registration(generation)
        assert_bounded_files(generation)
        assert_units_after_activation()

    def stop_managed_runtime() -> None:
        machine.succeed(
            "systemctl stop dgx-setup-canary.service system-manager.target "
            "sysinit-reactivation.target"
        )
        for unit in managed_units:
            machine.fail(f"systemctl is-active --quiet '{unit}'")

    def restart_container() -> None:
        machine.shutdown()
        machine.__dict__.pop("container_pid", None)
        machine.start()
        machine.wait_for_boot()
        machine.wait_for_unit("default.target")

    def assert_post_restart(*, boot_enabled: bool) -> None:
        if boot_enabled:
            machine.wait_for_unit("system-manager.target")
            machine.wait_for_unit("dgx-setup-canary.service")
            machine.succeed(
                "systemctl is-active --quiet system-manager.target "
                "dgx-setup-canary.service"
            )
        else:
            machine.fail("systemctl is-active --quiet system-manager.target")
            machine.fail("systemctl is-active --quiet dgx-setup-canary.service")
        machine.fail("systemctl is-active --quiet sysinit-reactivation.target")
        for unit in managed_units:
            machine.succeed(
                f"test \"$(systemctl show '{unit}' -p NeedDaemonReload --value)\" "
                "= no"
            )

    machine.succeed(
        "echo 'f /run/dgx-unmanaged-tmpfiles-sentinel 0644 root root - blocked' "
        "> /etc/tmpfiles.d/dgx-unmanaged.conf"
    )
    protected_before = protected_snapshot()
    machine.succeed(f"ln -s -- '{generation_one}' '{generation_one_root}'")
    activation_logs = machine.succeed(f"'{generation_one}/bin/activate'")
    assert "ERROR" not in activation_logs, activation_logs
    run_first("apply-first")
    machine.succeed(f"ln -s -- '{generation_two}' '{generation_two_root}'")
    run_switch("apply-switch")
    machine.wait_for_unit("system-manager.target")
    machine.wait_for_unit("dgx-setup-canary.service")

    with subtest("Registered generation two refuses an unretained boot candidate"):
        assert_absent(generation_three_root)
        run_boot("apply-boot", expect_success=False)
        assert raw_link(profile_path) == "system-manager-2-link"
        assert raw_link(gcroot_path) == generation_two
        assert_bounded_files(2)

    machine.succeed(
        f"ln -s -- '{generation_three}' '{generation_three_root}'"
    )

    with subtest("Exact generation-two boot transaction pre-state verifies"):
        run_boot("verify-before")
        assert_generation(2)

    with subtest("Unknown profile entries refuse boot activation without mutation"):
        machine.succeed(f"printf foreign > '{profile_dir}/foreign-entry'")
        run_boot("apply-boot", expect_success=False)
        machine.succeed(f"grep -Fx foreign '{profile_dir}/foreign-entry'")
        machine.succeed(f"unlink '{profile_dir}/foreign-entry'")
        assert_generation(2)

    with subtest("Upstream partial advancement preserves a foreign root collision"):
        run_boot(
            "apply-boot",
            failure_stage="upstream-gcroot-collision",
            expect_success=False,
        )
        assert profile_entries() == [
            "system-manager",
            "system-manager-1-link",
            "system-manager-2-link",
        ]
        machine.succeed(f"test -f '{gcroot_path}'")
        machine.succeed(
            f"grep -Fx disposable-foreign-collision '{gcroot_path}'"
        )
        assert_bounded_files(2)
        machine.succeed(f"unlink '{gcroot_path}'")
        machine.succeed(f"ln -s -- '{generation_two}' '{gcroot_path}'")
        assert_generation(2)

    with subtest("Failure after registration restores exact generation two"):
        run_boot(
            "apply-boot",
            failure_stage="after-registration",
            expect_success=False,
        )
        assert_generation(2)

    with subtest("Failure after boot-edge activation restores exact generation two"):
        run_boot(
            "apply-boot",
            failure_stage="after-activation",
            expect_success=False,
        )
        assert_generation(2)

    with subtest("Successful apply selects generation three and installs one boot edge"):
        run_boot("apply-boot")
        run_boot("verify-after")
        assert_generation(3)

    with subtest("Duplicate apply refuses and preserves generation three"):
        run_boot("apply-boot", expect_success=False)
        assert_generation(3)

    with subtest("Rollback refuses a foreign root before changing live state"):
        machine.succeed(f"unlink '{gcroot_path}'")
        machine.succeed(
            f"printf disposable-foreign-collision > '{gcroot_path}'"
        )
        run_boot("rollback-boot", expect_success=False)
        machine.succeed(f"test -f '{gcroot_path}'")
        machine.succeed(
            f"grep -Fx disposable-foreign-collision '{gcroot_path}'"
        )
        assert_bounded_files(3)
        assert_units_after_activation()
        machine.succeed(f"unlink '{gcroot_path}'")
        machine.succeed(f"ln -s -- '{generation_three}' '{gcroot_path}'")
        assert_generation(3)

    with subtest("A fresh container boot starts only the boot-persistent canary"):
        # The sentinel has already proved that every explicit activation skips
        # unmanaged tmpfiles. Remove its boot-time rule before restarting: the
        # distro's normal systemd-tmpfiles-setup service is expected to process
        # /etc/tmpfiles.d during a real boot and is outside this regression.
        machine.succeed("unlink /etc/tmpfiles.d/dgx-unmanaged.conf")
        assert_absent(unmanaged_tmpfiles_sentinel)
        stop_managed_runtime()
        restart_container()
        assert_registration(3)
        assert_bounded_files(3)
        assert_post_restart(boot_enabled=True)

    with subtest("Rollback after reboot restores exact no-boot generation two"):
        run_boot("rollback-boot")
        run_boot("rollback-boot")
        run_boot("verify-before")
        assert_generation(2)

    with subtest("A fresh container boot proves rollback removed persistence"):
        stop_managed_runtime()
        restart_container()
        assert_registration(2)
        assert_bounded_files(2)
        assert_post_restart(boot_enabled=False)

    with subtest("Disposable cleanup restores empty unregistered manager state"):
        machine.succeed(f"'{generation_two}/bin/activate'")
        assert_generation(2)
        run_switch("rollback-switch")
        run_first("rollback-first")
        machine.succeed(f"'{generation_one}/bin/deactivate'")
        machine.succeed(f"unlink '{generation_three_root}'")
        machine.succeed(f"unlink '{generation_two_root}'")
        machine.succeed(f"unlink '{generation_one_root}'")
        assert_absent(profile_dir)
        assert_absent(gcroot_path)
        for path in managed_common_paths + [boot_link]:
            assert_absent(path)
        state = json.loads(machine.succeed(f"cat '{state_path}'"))
        assert state == {
            "fileTree": {"files": [], "backedUpFiles": []},
            "services": {},
            "version": 0,
        }
        for path in forbidden_paths:
            assert_absent(path)
        assert_absent(unmanaged_tmpfiles_sentinel)
        assert protected_snapshot() == protected_before
  '';
}
