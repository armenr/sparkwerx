{
  system-manager,
  pkgs,
  rootManagerOverlays,
  rootCanary,
  rootDesktopModeTransactionProgram,
}:

let
  fakeTailscaled = pkgs.writeShellScript "tailscaled-desktop-transaction-fixture" ''
    set -eu

    if [ "''${1-}" = --cleanup ]; then
      exit 0
    fi

    printf '%s\n' nix-managed > /run/tailscale/provider
    ${pkgs.systemdMinimal}/bin/systemd-notify --ready
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';

  fakeTailscalePackage = pkgs.runCommand "tailscale-desktop-transaction-fixture-1.102.3" { } ''
    mkdir -p "$out/bin"
    ln -s ${fakeTailscaled} "$out/bin/tailscaled"
  '';

  fakeGdm = pkgs.writeShellScript "gdm-desktop-transaction-fixture" ''
    set -eu
    printf '%s\n' factory-gnome > /run/dgx-fake-gdm
    ${pkgs.systemdMinimal}/bin/systemd-notify --ready
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';

  fakeGdmUnit = pkgs.writeText "gdm-desktop-transaction-fixture.service" ''
    [Unit]
    Description=Factory GDM desktop-transaction fixture
    After=systemd-user-sessions.service

    [Service]
    Type=notify
    ExecStart=${fakeGdm}
    ExecStopPost=${pkgs.coreutils}/bin/rm -f /run/dgx-fake-gdm
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
in
system-manager.lib.containerTest.makeContainerTest {
  hostPkgs = pkgs;
  name = "dgx-desktop-headless-transaction";
  toplevel = rootCanary;
  extraPathsToRegister = [
    fakeGdm
    fakeGdmUnit
    generationOne
    generationTwo
    generationThree
    generationFour
    headlessGeneration
    rootDesktopModeTransactionProgram
  ];
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")

    generation_one = "${generationOne}"
    generation_two = "${generationTwo}"
    generation_three = "${generationThree}"
    generation_four = "${generationFour}"
    headless = "${headlessGeneration}"
    transaction = "${rootDesktopModeTransactionProgram}"
    profile_dir = "/nix/var/nix/profiles/system-manager-profiles"
    profile_path = f"{profile_dir}/system-manager"
    gcroot_path = "/nix/var/nix/gcroots/system-manager-current"
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
    }
    headless_root = (
        "/nix/var/nix/gcroots/dgx-setup-desktop-headless-pilot"
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

    def raw_link(path: str) -> str:
        return machine.succeed(f"readlink -- '{path}'").strip()

    def profile_entries() -> list[str]:
        return machine.succeed(
            f"find '{profile_dir}' -mindepth 1 -maxdepth 1 "
            "-printf '%f\\n' | sort"
        ).splitlines()

    def run_transaction(
        action: str,
        *,
        failure_stage: str | None = None,
        expect_success: bool = True,
    ) -> str:
        injection = ""
        if failure_stage is not None:
            injection = (
                "DGX_DESKTOP_MODE_TEST_FAIL_STAGE="
                f"'{failure_stage}' "
            )
        command = (
            "env NIX_USER_CONF_FILES=/dev/null "
            f"{injection}/bin/bash '{transaction}' '{action}' "
            f"'{generation_one}' '{generation_two}' "
            f"'{generation_three}' '{generation_four}' '{headless}'"
        )
        if expect_success:
            return machine.succeed(command)
        return machine.fail(command)

    def assert_factory() -> None:
        run_transaction("verify-factory")
        assert profile_entries() == [
            "system-manager",
            "system-manager-1-link",
            "system-manager-2-link",
            "system-manager-3-link",
            "system-manager-4-link",
        ]
        assert raw_link(profile_path) == "system-manager-4-link"
        assert raw_link(gcroot_path) == generation_four
        machine.succeed("grep -Fx factory-gnome /run/dgx-fake-gdm")
        assert raw_link(headless_root) == headless
        assert machine.succeed(
            "systemctl show tailscaled.service -p MainPID --value"
        ).strip() == tailscale_pid
        assert protected_snapshot() == protected_before

    def assert_headless() -> None:
        run_transaction("verify-headless")
        assert profile_entries() == [
            "system-manager",
            "system-manager-1-link",
            "system-manager-2-link",
            "system-manager-3-link",
            "system-manager-4-link",
            "system-manager-5-link",
        ]
        assert raw_link(profile_path) == "system-manager-5-link"
        assert raw_link(gcroot_path) == headless
        machine.fail("test -e /run/dgx-fake-gdm")
        assert machine.succeed(
            "systemctl show tailscaled.service -p MainPID --value"
        ).strip() == tailscale_pid
        assert protected_snapshot() == protected_before

    machine.succeed("install -d -m 0755 /usr/lib/systemd/system")
    machine.succeed(
        "install -m 0644 '${fakeGdmUnit}' /usr/lib/systemd/system/gdm.service"
    )
    machine.succeed("install -d -m 0755 /etc/systemd/system")
    machine.succeed(
        "ln -s /usr/lib/systemd/system/gdm.service "
        "/etc/systemd/system/display-manager.service"
    )
    machine.succeed("systemctl daemon-reload")
    machine.succeed("systemctl start gdm.service")
    machine.wait_for_unit("gdm.service")

    for root, candidate in roots.items():
        machine.succeed(f"ln -s -- '{candidate}' '{root}'")

    activation_logs = machine.succeed(f"'{generation_one}/bin/activate'")
    assert "ERROR" not in activation_logs, activation_logs
    for candidate in [
        generation_one,
        generation_two,
        generation_three,
        generation_four,
    ]:
        machine.succeed(f"'{candidate}/bin/register-profile'")
    activation_logs = machine.succeed(f"'{generation_four}/bin/activate'")
    assert "ERROR" not in activation_logs, activation_logs
    machine.wait_for_unit("system-manager.target")
    machine.wait_for_unit("tailscaled.service")
    machine.succeed("systemctl start graphical.target gdm.service")
    machine.wait_for_unit("gdm.service")
    protected_before = protected_snapshot()
    tailscale_pid = machine.succeed(
        "systemctl show tailscaled.service -p MainPID --value"
    ).strip()

    with subtest("Unretained headless candidate refuses before mutation"):
        run_transaction("apply-headless", expect_success=False)
        machine.fail(f"test -e '{headless_root}' || test -L '{headless_root}'")
        assert raw_link(profile_path) == "system-manager-4-link"
        assert raw_link(gcroot_path) == generation_four

    machine.succeed(f"ln -s -- '{headless}' '{headless_root}'")

    with subtest("Exact generation-four factory pre-state verifies"):
        assert_factory()

    with subtest("Unknown profile entries refuse without mutation"):
        machine.succeed(f"printf foreign > '{profile_dir}/foreign-entry'")
        run_transaction("apply-headless", expect_success=False)
        machine.succeed(f"grep -Fx foreign '{profile_dir}/foreign-entry'")
        machine.succeed(f"unlink '{profile_dir}/foreign-entry'")
        assert_factory()

    with subtest("Partial registration preserves a foreign root collision"):
        run_transaction(
            "apply-headless",
            failure_stage="upstream-gcroot-collision",
            expect_success=False,
        )
        assert profile_entries() == [
            "system-manager",
            "system-manager-1-link",
            "system-manager-2-link",
            "system-manager-3-link",
            "system-manager-4-link",
        ]
        machine.succeed(f"test -f '{gcroot_path}'")
        machine.succeed(
            f"grep -Fx disposable-foreign-collision '{gcroot_path}'"
        )
        machine.succeed(f"unlink '{gcroot_path}'")
        machine.succeed(f"ln -s -- '{generation_four}' '{gcroot_path}'")
        assert_factory()

    for stage, title in [
        (
            "after-registration",
            "Failure after registration restores exact factory state",
        ),
        (
            "after-activation",
            "Failure after activation restores exact factory state",
        ),
        (
            "after-isolate",
            "Failure after isolation restores exact factory state",
        ),
    ]:
        with subtest(title):
            run_transaction(
                "apply-headless",
                failure_stage=stage,
                expect_success=False,
            )
            assert_factory()

    with subtest("Successful transaction retains exact headless generation five"):
        run_transaction("apply-headless")
        assert_headless()

    with subtest("Duplicate headless apply refuses without mutation"):
        run_transaction("apply-headless", expect_success=False)
        assert_headless()

    with subtest("Factory rollback refuses a foreign upstream root"):
        machine.succeed(f"unlink '{gcroot_path}'")
        machine.succeed(
            f"printf disposable-foreign-collision > '{gcroot_path}'"
        )
        run_transaction("rollback-factory", expect_success=False)
        machine.succeed(f"test -f '{gcroot_path}'")
        machine.succeed(
            f"grep -Fx disposable-foreign-collision '{gcroot_path}'"
        )
        machine.succeed(f"unlink '{gcroot_path}'")
        machine.succeed(f"ln -s -- '{headless}' '{gcroot_path}'")
        assert_headless()

    with subtest("Exact rollback is idempotent and restores factory GNOME"):
        run_transaction("rollback-factory")
        run_transaction("rollback-factory")
        assert_factory()

    with subtest("All retained roots and protected state remain exact"):
        for root, candidate in roots.items():
            assert raw_link(root) == candidate
        assert raw_link(headless_root) == headless
        machine.succeed("grep -Fx nix-managed /run/tailscale/provider")
        assert protected_snapshot() == protected_before
  '';
}
