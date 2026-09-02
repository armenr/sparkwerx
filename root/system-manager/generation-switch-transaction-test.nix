{
  system-manager,
  pkgs,
  rootCanary,
  rootCanaryRegistrationTestGeneration,
  rootRegistrationTransactionProgram,
  rootGenerationSwitchTransactionProgram,
}:

system-manager.lib.containerTest.makeContainerTest {
  hostPkgs = pkgs;
  name = "dgx-root-canary-generation-switch-transaction";
  toplevel = rootCanary;
  extraPathsToRegister = [
    rootCanaryRegistrationTestGeneration
    rootRegistrationTransactionProgram
    rootGenerationSwitchTransactionProgram
  ];
  testScript = ''
    import json

    start_all()
    machine.wait_for_unit("multi-user.target")

    generation_one = "${rootCanary}"
    generation_two = "${rootCanaryRegistrationTestGeneration}"
    first_registration = "${rootRegistrationTransactionProgram}"
    generation_switch = "${rootGenerationSwitchTransactionProgram}"
    state_path = "/var/lib/system-manager/state/system-manager-state.json"
    profile_dir = "/nix/var/nix/profiles/system-manager-profiles"
    profile_path = f"{profile_dir}/system-manager"
    generation_one_path = f"{profile_dir}/system-manager-1-link"
    generation_two_path = f"{profile_dir}/system-manager-2-link"
    gcroot_path = "/nix/var/nix/gcroots/system-manager-current"
    pilot_root = "/nix/var/nix/gcroots/dgx-setup-root-canary-pilot"
    generation_two_root = (
        "/nix/var/nix/gcroots/"
        "dgx-setup-root-canary-generation-two-pilot"
    )
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

    def expected_live_links(candidate: str) -> dict[str, str]:
        etc_map = json.loads(
            machine.succeed(f"cat '{candidate}/etcFiles/etcFiles.json'")
        )
        service_map = json.loads(
            machine.succeed(f"cat '{candidate}/services/services.json'")
        )
        canary_source = etc_map["entries"]["dgx-setup/canary"]["source"]
        service_source = service_map["dgx-setup-canary.service"]["storePath"]
        return {
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
                service_map["system-manager.target"]["storePath"]
            ),
            (
                "/etc/systemd/system/system-manager.target.wants/"
                "dgx-setup-canary.service"
            ): resolved(service_source),
        }

    def run_first(action: str, *, expect_success: bool = True) -> str:
        command = (
            "env NIX_USER_CONF_FILES=/dev/null "
            f"/bin/bash '{first_registration}' '{action}' '{generation_one}'"
        )
        if expect_success:
            return machine.succeed(command)
        return machine.fail(command)

    def run_switch(
        action: str,
        *,
        failure_stage: str | None = None,
        expect_success: bool = True,
    ) -> str:
        injection = ""
        if failure_stage is not None:
            injection = (
                "DGX_GENERATION_SWITCH_TEST_FAIL_STAGE="
                f"'{failure_stage}' "
            )
        command = (
            "env NIX_USER_CONF_FILES=/dev/null "
            f"{injection}/bin/bash '{generation_switch}' '{action}' "
            f"'{generation_one}' '{generation_two}'"
        )
        if expect_success:
            return machine.succeed(command)
        return machine.fail(command)

    def assert_bounded_live(generation: int) -> None:
        candidate = generation_two if generation == 2 else generation_one
        state = json.loads(machine.succeed(f"cat '{state_path}'"))
        assert state["version"] == 1
        assert set(state["fileTree"]["files"]) == set(managed_paths)
        assert state["fileTree"]["backedUpFiles"] == []
        assert set(state["services"].keys()) == set(managed_units)
        machine.succeed("grep -Fx 'host=sparkle-01' /etc/dgx-setup/canary")
        marker_command = (
            "grep -Fx 'registration-test-generation=2' "
            "/etc/dgx-setup/canary"
        )
        if generation == 2:
            machine.succeed(marker_command)
        else:
            machine.fail(marker_command)
        for path in managed_paths:
            machine.succeed(f"test -L '{path}'")
        assert {
            path: resolved(path) for path in managed_paths
        } == expected_live_links(candidate)
        for path in forbidden_paths:
            assert_absent(path)
        assert_absent(unmanaged_tmpfiles_sentinel)
        for unit in managed_units:
            machine.succeed(
                f"test \"$(systemctl show '{unit}' -p ActiveState --value)\" "
                "= active"
            )
            machine.succeed(
                f"test \"$(systemctl show '{unit}' -p NeedDaemonReload --value)\" "
                "= no"
            )

    def assert_generation_one() -> None:
        assert profile_entries() == [
            "system-manager",
            "system-manager-1-link",
        ]
        assert raw_link(profile_path) == "system-manager-1-link"
        assert raw_link(generation_one_path) == generation_one
        assert raw_link(gcroot_path) == generation_one
        assert raw_link(pilot_root) == generation_one
        assert raw_link(generation_two_root) == generation_two
        assert resolved(profile_path) == generation_one
        assert_bounded_live(1)
        assert protected_snapshot() == protected_before

    def assert_generation_two() -> None:
        assert profile_entries() == [
            "system-manager",
            "system-manager-1-link",
            "system-manager-2-link",
        ]
        assert raw_link(profile_path) == "system-manager-2-link"
        assert raw_link(generation_one_path) == generation_one
        assert raw_link(generation_two_path) == generation_two
        assert raw_link(gcroot_path) == generation_two
        assert raw_link(pilot_root) == generation_one
        assert raw_link(generation_two_root) == generation_two
        assert resolved(profile_path) == generation_two
        assert_bounded_live(2)
        assert protected_snapshot() == protected_before

    machine.succeed(
        "echo 'f /run/dgx-unmanaged-tmpfiles-sentinel 0644 root root - blocked' "
        "> /etc/tmpfiles.d/dgx-unmanaged.conf"
    )
    protected_before = protected_snapshot()
    machine.succeed(f"ln -s -- '{generation_one}' '{pilot_root}'")
    activation_logs = machine.succeed(f"'{generation_one}/bin/activate'")
    assert "ERROR" not in activation_logs, activation_logs
    run_first("apply-first")
    machine.wait_for_unit("system-manager.target")
    machine.wait_for_unit("dgx-setup-canary.service")

    with subtest("Registered generation one refuses an unretained candidate"):
        assert_absent(generation_two_root)
        run_switch("apply-switch", expect_success=False)
        machine.succeed(f"test -L '{profile_path}'")
        assert raw_link(profile_path) == "system-manager-1-link"
        assert raw_link(gcroot_path) == generation_one
        assert_bounded_live(1)
        assert protected_snapshot() == protected_before

    machine.succeed(
        f"ln -s -- '{generation_two}' '{generation_two_root}'"
    )

    with subtest("Exact generation-one switch pre-state verifies"):
        run_switch("verify-before")
        assert_generation_one()

    with subtest("Unknown profile entries refuse switching without mutation"):
        machine.succeed(f"printf foreign > '{profile_dir}/foreign-entry'")
        run_switch("apply-switch", expect_success=False)
        machine.succeed(f"grep -Fx foreign '{profile_dir}/foreign-entry'")
        machine.succeed(f"unlink '{profile_dir}/foreign-entry'")
        assert_generation_one()

    with subtest("Upstream partial advancement preserves a foreign collision"):
        run_switch(
            "apply-switch",
            failure_stage="upstream-gcroot-collision",
            expect_success=False,
        )
        assert profile_entries() == [
            "system-manager",
            "system-manager-1-link",
        ]
        assert raw_link(profile_path) == "system-manager-1-link"
        assert resolved(profile_path) == generation_one
        machine.succeed(f"test -f '{gcroot_path}'")
        machine.succeed(
            f"grep -Fx disposable-foreign-collision '{gcroot_path}'"
        )
        assert_bounded_live(1)
        assert protected_snapshot() == protected_before
        machine.succeed(f"unlink '{gcroot_path}'")
        machine.succeed(f"ln -s -- '{generation_one}' '{gcroot_path}'")
        assert_generation_one()

    with subtest("Failure after registration restores exact generation one"):
        run_switch(
            "apply-switch",
            failure_stage="after-registration",
            expect_success=False,
        )
        assert_generation_one()

    with subtest("Failure after activation restores exact generation one"):
        run_switch(
            "apply-switch",
            failure_stage="after-activation",
            expect_success=False,
        )
        assert_generation_one()

    with subtest("A successful switch selects, roots, and activates generation two"):
        run_switch("apply-switch")
        run_switch("verify-after")
        assert_generation_two()

    with subtest("Duplicate apply refuses and preserves generation two"):
        run_switch("apply-switch", expect_success=False)
        assert_generation_two()

    with subtest("Rollback refuses a foreign root before changing live state"):
        machine.succeed(f"unlink '{gcroot_path}'")
        machine.succeed(
            f"printf disposable-foreign-collision > '{gcroot_path}'"
        )
        run_switch("rollback-switch", expect_success=False)
        machine.succeed(f"test -f '{gcroot_path}'")
        machine.succeed(
            f"grep -Fx disposable-foreign-collision '{gcroot_path}'"
        )
        assert raw_link(profile_path) == "system-manager-2-link"
        assert_bounded_live(2)
        assert protected_snapshot() == protected_before
        machine.succeed(f"unlink '{gcroot_path}'")
        machine.succeed(f"ln -s -- '{generation_two}' '{gcroot_path}'")
        assert_generation_two()

    with subtest("Exact rollback is idempotent and restores generation one"):
        run_switch("rollback-switch")
        run_switch("rollback-switch")
        run_switch("verify-before")
        assert_generation_one()

    with subtest("Disposable cleanup restores empty unregistered manager state"):
        run_first("rollback-first")
        machine.succeed(f"'{generation_one}/bin/deactivate'")
        machine.succeed(f"unlink '{generation_two_root}'")
        machine.succeed(f"unlink '{pilot_root}'")
        assert_absent(profile_dir)
        assert_absent(gcroot_path)
        for path in managed_paths:
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
