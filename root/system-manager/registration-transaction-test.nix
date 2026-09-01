{
  system-manager,
  pkgs,
  rootCanary,
  rootRegistrationTransactionProgram,
}:

system-manager.lib.containerTest.makeContainerTest {
  hostPkgs = pkgs;
  name = "dgx-root-canary-registration-transaction";
  toplevel = rootCanary;
  extraPathsToRegister = [ rootRegistrationTransactionProgram ];
  testScript = ''
    import json

    start_all()
    machine.wait_for_unit("multi-user.target")

    generation = "${rootCanary}"
    transaction = "${rootRegistrationTransactionProgram}"
    state_path = "/var/lib/system-manager/state/system-manager-state.json"
    profile_dir = "/nix/var/nix/profiles/system-manager-profiles"
    profile_path = f"{profile_dir}/system-manager"
    generation_path = f"{profile_dir}/system-manager-1-link"
    gcroot_path = "/nix/var/nix/gcroots/system-manager-current"
    pilot_root = "/nix/var/nix/gcroots/dgx-setup-root-canary-pilot"
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

    def run_transaction(
        action: str,
        *,
        failure_stage: str | None = None,
        expect_success: bool = True,
    ) -> str:
        injection = ""
        if failure_stage is not None:
            injection = f"DGX_REGISTRATION_TEST_FAIL_STAGE='{failure_stage}' "
        command = (
            "env NIX_USER_CONF_FILES=/dev/null "
            f"{injection}/bin/bash '{transaction}' '{action}' '{generation}'"
        )
        if expect_success:
            return machine.succeed(command)
        return machine.fail(command)

    def assert_unregistered() -> None:
        assert_absent(profile_dir)
        assert_absent(gcroot_path)

    def assert_bounded_live_state() -> None:
        state = json.loads(machine.succeed(f"cat '{state_path}'"))
        assert state["version"] == 1
        assert set(state["fileTree"]["files"]) == set(managed_paths)
        assert state["fileTree"]["backedUpFiles"] == []
        assert set(state["services"].keys()) == {
            "dgx-setup-canary.service",
            "sysinit-reactivation.target",
            "system-manager.target",
        }
        machine.succeed("grep -Fx 'host=sparkle-01' /etc/dgx-setup/canary")
        for path in managed_paths:
            machine.succeed(f"test -L '{path}'")
        assert {path: resolved(path) for path in managed_paths} == live_links_before
        for path in forbidden_paths:
            assert_absent(path)
        assert_absent(unmanaged_tmpfiles_sentinel)
        machine.succeed(f"test -L '{pilot_root}'")
        assert machine.succeed(f"readlink -- '{pilot_root}'").strip() == generation
        machine.wait_for_unit("system-manager.target")
        machine.wait_for_unit("dgx-setup-canary.service")

    machine.succeed(
        "echo 'f /run/dgx-unmanaged-tmpfiles-sentinel 0644 root root - blocked' "
        "> /etc/tmpfiles.d/dgx-unmanaged.conf"
    )
    before = protected_snapshot()
    machine.succeed(f"ln -s -- '{generation}' '{pilot_root}'")

    activation_logs = machine.succeed(f"'{generation}/bin/activate'")
    assert "ERROR" not in activation_logs, activation_logs
    machine.wait_for_unit("system-manager.target")
    machine.wait_for_unit("dgx-setup-canary.service")
    live_links_before = {path: resolved(path) for path in managed_paths}

    with subtest("Active retained canary begins exactly unregistered"):
        run_transaction("verify-absent")
        assert_unregistered()
        assert_bounded_live_state()
        assert protected_snapshot() == before

    with subtest("A preflight GC-root collision causes no profile mutation"):
        machine.succeed(f"printf preexisting > '{gcroot_path}'")
        run_transaction("apply-first", expect_success=False)
        assert_absent(profile_dir)
        machine.succeed(f"test -f '{gcroot_path}'")
        machine.succeed(f"grep -Fx preexisting '{gcroot_path}'")
        machine.succeed(f"unlink '{gcroot_path}'")
        assert_unregistered()
        assert_bounded_live_state()
        assert protected_snapshot() == before

    with subtest("Upstream partial profile advancement is exactly reconciled"):
        run_transaction(
            "apply-first",
            failure_stage="upstream-gcroot-collision",
            expect_success=False,
        )
        assert_absent(profile_dir)
        machine.succeed(f"test -f '{gcroot_path}'")
        machine.succeed(
            f"grep -Fx disposable-foreign-collision '{gcroot_path}'"
        )
        machine.succeed(f"unlink '{gcroot_path}'")
        assert_unregistered()
        assert_bounded_live_state()
        assert protected_snapshot() == before

    with subtest("Failure after complete registration restores absence"):
        run_transaction(
            "apply-first",
            failure_stage="after-registration",
            expect_success=False,
        )
        assert_unregistered()
        assert_bounded_live_state()
        assert protected_snapshot() == before

    with subtest("Missing exact pilot retention refuses registration"):
        machine.succeed(f"unlink '{pilot_root}'")
        run_transaction("apply-first", expect_success=False)
        assert_unregistered()
        machine.succeed(f"ln -s -- '{generation}' '{pilot_root}'")
        assert_bounded_live_state()
        assert protected_snapshot() == before

    with subtest("Rollback refuses unknown profile content without deleting it"):
        machine.succeed(f"mkdir '{profile_dir}'")
        machine.succeed(f"printf foreign > '{profile_dir}/foreign-entry'")
        run_transaction("rollback-first", expect_success=False)
        machine.succeed(f"grep -Fx foreign '{profile_dir}/foreign-entry'")
        machine.succeed(f"unlink '{profile_dir}/foreign-entry'")
        machine.succeed(f"rmdir '{profile_dir}'")
        assert_unregistered()
        assert_bounded_live_state()
        assert protected_snapshot() == before

    with subtest("First generation registers without changing live activation"):
        run_transaction("apply-first")
        run_transaction("verify-first")
        machine.succeed(f"test -L '{profile_path}'")
        machine.succeed(f"test -L '{generation_path}'")
        machine.succeed(f"test -L '{gcroot_path}'")
        assert resolved(profile_path) == generation
        assert resolved(generation_path) == generation
        assert resolved(gcroot_path) == generation
        entries = machine.succeed(
            f"find '{profile_dir}' -mindepth 1 -maxdepth 1 -printf '%f\\n' | sort"
        ).splitlines()
        assert entries == ["system-manager", "system-manager-1-link"], entries
        assert_bounded_live_state()
        assert protected_snapshot() == before

    with subtest("Exact rollback restores active unregistered state"):
        run_transaction("rollback-first")
        run_transaction("rollback-first")
        assert_unregistered()
        assert_bounded_live_state()
        assert protected_snapshot() == before

    with subtest("Disposable cleanup leaves bounded empty manager state"):
        machine.succeed(f"'{generation}/bin/deactivate'")
        machine.succeed(f"unlink '{pilot_root}'")
        for path in managed_paths:
            assert_absent(path)
        assert_unregistered()
        state = json.loads(machine.succeed(f"cat '{state_path}'"))
        assert state == {
            "fileTree": {"files": [], "backedUpFiles": []},
            "services": {},
            "version": 0,
        }
        for path in forbidden_paths:
            assert_absent(path)
        assert_absent(unmanaged_tmpfiles_sentinel)
        assert protected_snapshot() == before
  '';
}
