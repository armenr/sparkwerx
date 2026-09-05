{
  system-manager,
  pkgs,
  rootManagerOverlays,
  rootCanary,
}:

let
  fakeTailscaled = pkgs.writeShellScript "tailscaled-desktop-fixture" ''
    set -eu

    if [ "''${1-}" = --cleanup ]; then
      exit 0
    fi

    printf '%s\n' nix-managed > /run/tailscale/provider
    ${pkgs.systemdMinimal}/bin/systemd-notify --ready
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';

  fakeTailscalePackage = pkgs.runCommand "tailscale-desktop-fixture-1.102.3" { } ''
    mkdir -p "$out/bin"
    ln -s ${fakeTailscaled} "$out/bin/tailscaled"
  '';

  fakeGdm = pkgs.writeShellScript "gdm-desktop-fixture" ''
    set -eu
    printf '%s\n' factory-gnome > /run/dgx-fake-gdm
    ${pkgs.systemdMinimal}/bin/systemd-notify --ready
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';

  fakeGdmUnit = pkgs.writeText "gdm-desktop-fixture.service" ''
    [Unit]
    Description=Factory GDM disposable fixture
    After=systemd-user-sessions.service

    [Service]
    Type=notify
    ExecStart=${fakeGdm}
    ExecStopPost=${pkgs.coreutils}/bin/rm -f /run/dgx-fake-gdm
  '';

  mkTestGeneration =
    mode:
    system-manager.lib.makeSystemConfig {
      overlays = rootManagerOverlays;
      modules = [
        ../../hosts/sparkle-01/system.nix
        {
          dgx.root = {
            bootPersistence.enable = true;
            tailscale = {
              enable = true;
              package = fakeTailscalePackage;
              sshDesired = true;
            };
          }
          // pkgs.lib.optionalAttrs (mode != null) {
            desktop = {
              enable = true;
              inherit mode;
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
            ${pkgs.lib.optionalString (mode != null) ''
              desktop-controller-generation=5
                            desktop-mode=${mode}''}
          '';
        }
      ];
    };

  generationFour = mkTestGeneration null;
  headlessGeneration = mkTestGeneration "headless";
  gnomeGeneration = mkTestGeneration "gnome";
in
system-manager.lib.containerTest.makeContainerTest {
  hostPkgs = pkgs;
  name = "dgx-desktop-mode-lifecycle";
  toplevel = rootCanary;
  extraPathsToRegister = [
    fakeGdm
    fakeGdmUnit
    generationFour
    headlessGeneration
    gnomeGeneration
  ];
  testScript = ''
    import json

    start_all()
    machine.wait_for_unit("multi-user.target")

    generation_four = "${generationFour}"
    headless_generation = "${headlessGeneration}"
    gnome_generation = "${gnomeGeneration}"
    state_path = "/var/lib/system-manager/state/system-manager-state.json"
    default_alias = "/etc/systemd/system/default.target"
    desktop_marker = "/etc/dgx-setup/desktop-mode"
    headless_target_path = "/etc/systemd/system/dgx-headless.target"
    gnome_target_path = "/etc/systemd/system/dgx-gnome.target"
    managed_tailscale = "/etc/systemd/system/tailscaled.service"

    generation_four_paths = {
        "/etc/dgx-setup/canary",
        "/etc/systemd/system/default.target.wants/system-manager.target",
        "/etc/systemd/system/dgx-setup-canary.service",
        "/etc/systemd/system/sysinit-reactivation.target",
        "/etc/systemd/system/system-manager.target",
        (
            "/etc/systemd/system/system-manager.target.wants/"
            "dgx-setup-canary.service"
        ),
        (
            "/etc/systemd/system/system-manager.target.wants/"
            "tailscaled.service"
        ),
        managed_tailscale,
    }
    desktop_paths = generation_four_paths | {
        default_alias,
        desktop_marker,
        headless_target_path,
        gnome_target_path,
    }
    generation_four_units = {
        "dgx-setup-canary.service",
        "sysinit-reactivation.target",
        "system-manager.target",
        "tailscaled.service",
    }
    desktop_units = generation_four_units | {
        "dgx-headless.target",
        "dgx-gnome.target",
    }

    def assert_absent(path: str) -> None:
        machine.fail(f"test -e '{path}' || test -L '{path}'")

    def active(unit: str) -> None:
        machine.succeed(f"systemctl is-active --quiet '{unit}'")

    def inactive(unit: str) -> None:
        machine.fail(f"systemctl is-active --quiet '{unit}'")

    def property_value(unit: str, prop: str) -> str:
        return machine.succeed(
            f"systemctl show '{unit}' -p '{prop}' --value"
        ).strip()

    def tailscale_pid() -> str:
        return property_value("tailscaled.service", "MainPID")

    def assert_tailscale() -> None:
        active("tailscaled.service")
        assert property_value("tailscaled.service", "FragmentPath") == (
            managed_tailscale
        )
        machine.succeed("grep -Fx nix-managed /run/tailscale/provider")

    def assert_manager_state(*, desktop: bool) -> None:
        state = json.loads(machine.succeed(f"cat '{state_path}'"))
        assert state["version"] == 1
        assert set(state["fileTree"]["files"]) == (
            desktop_paths if desktop else generation_four_paths
        )
        assert state["fileTree"]["backedUpFiles"] == []
        assert set(state["services"].keys()) == (
            desktop_units if desktop else generation_four_units
        )

    def assert_default(mode: str) -> None:
        # System Manager materializes unit files as immutable links outside
        # systemd's unit search path. systemctl consequently classifies this
        # as a linked default.target unit and reports its lookup name rather
        # than the basename of the fully resolved target. Prove both the
        # expected report and the exact target instead of conflating them.
        reported_default = machine.succeed("systemctl get-default").strip()
        assert reported_default == "default.target", (
            "expected System Manager's linked default.target report; "
            f"observed {reported_default!r}"
        )
        machine.succeed(f"test -L '{default_alias}'")
        machine.succeed(
            f"test \"$(basename \"$(readlink -f '{default_alias}')\")\" "
            f"= 'dgx-{mode}.target'"
        )
        machine.succeed(f"grep -Fx 'mode={mode}' '{desktop_marker}'")
        machine.succeed(
            f"grep -Fx 'runtime-target=dgx-{mode}.target' '{desktop_marker}'"
        )

    def assert_mode(mode: str) -> None:
        assert_default(mode)
        active(f"dgx-{mode}.target")
        active("multi-user.target")
        active("system-manager.target")
        active("dgx-setup-canary.service")
        assert_tailscale()
        if mode == "headless":
            inactive("dgx-gnome.target")
            inactive("graphical.target")
            inactive("gdm.service")
            machine.fail("test -e /run/dgx-fake-gdm")
        else:
            inactive("dgx-headless.target")
            active("graphical.target")
            active("gdm.service")
            machine.succeed("grep -Fx factory-gnome /run/dgx-fake-gdm")
        machine.succeed("systemctl is-system-running --quiet")
        machine.succeed(
            "test -z \"$(systemctl list-units --state=failed "
            "--plain --no-legend)\""
        )
        assert_manager_state(desktop=True)

    def activate(candidate: str) -> str:
        logs = machine.succeed(f"'{candidate}/bin/activate'")
        assert "ERROR" not in logs, logs
        machine.wait_for_unit("system-manager.target")
        machine.wait_for_unit("dgx-setup-canary.service")
        machine.wait_for_unit("tailscaled.service")
        return logs

    def restart_container() -> None:
        machine.shutdown()
        machine.__dict__.pop("container_pid", None)
        machine.start()
        machine.wait_for_boot()
        machine.wait_for_unit("default.target")
        machine.wait_for_unit("system-manager.target")
        machine.wait_for_unit("tailscaled.service")

    with subtest("Install a factory-GDM fixture and exact generation four"):
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
        machine.succeed("systemctl daemon-reload")
        assert machine.succeed("systemctl get-default").strip() == (
            "graphical.target"
        )
        machine.succeed("systemctl start gdm.service")
        machine.wait_for_unit("gdm.service")
        activate(generation_four)
        active("graphical.target")
        active("gdm.service")
        assert_tailscale()
        assert_absent(default_alias)
        assert_absent(desktop_marker)
        assert_absent(headless_target_path)
        assert_absent(gnome_target_path)
        assert_manager_state(desktop=False)
        initial_tailscale_pid = tailscale_pid()

    with subtest("Declaring headless changes persistence but not the live target"):
        activate(headless_generation)
        assert_default("headless")
        active("graphical.target")
        active("gdm.service")
        inactive("dgx-headless.target")
        assert tailscale_pid() == initial_tailscale_pid
        assert_manager_state(desktop=True)

    with subtest("Headless isolate stops graphics and preserves managed access"):
        machine.succeed("systemctl isolate dgx-headless.target")
        machine.wait_for_unit("dgx-headless.target")
        assert_mode("headless")
        assert tailscale_pid() == initial_tailscale_pid

    with subtest("Headless mode persists across reboot"):
        restart_container()
        machine.wait_for_unit("dgx-headless.target")
        assert_mode("headless")
        headless_boot_tailscale_pid = tailscale_pid()

    with subtest("Declaring GNOME does not start graphics before convergence"):
        activate(gnome_generation)
        assert_default("gnome")
        active("dgx-headless.target")
        inactive("graphical.target")
        inactive("gdm.service")
        assert tailscale_pid() == headless_boot_tailscale_pid
        assert_manager_state(desktop=True)

    with subtest("GNOME isolate starts only the factory graphical stack"):
        machine.succeed("systemctl isolate dgx-gnome.target")
        machine.wait_for_unit("dgx-gnome.target")
        machine.wait_for_unit("gdm.service")
        assert_mode("gnome")
        assert tailscale_pid() == headless_boot_tailscale_pid

    with subtest("Factory GNOME mode persists across reboot"):
        restart_container()
        machine.wait_for_unit("dgx-gnome.target")
        machine.wait_for_unit("gdm.service")
        assert_mode("gnome")
        gnome_boot_tailscale_pid = tailscale_pid()

    with subtest("The same controller returns from GNOME to headless"):
        activate(headless_generation)
        active("gdm.service")
        machine.succeed("systemctl isolate dgx-headless.target")
        machine.wait_for_unit("dgx-headless.target")
        assert_mode("headless")
        assert tailscale_pid() == gnome_boot_tailscale_pid

    with subtest("Removing the controller restores the factory GNOME default"):
        activate(generation_four)
        assert_absent(default_alias)
        assert_absent(desktop_marker)
        assert_absent(headless_target_path)
        assert_absent(gnome_target_path)
        assert machine.succeed("systemctl get-default").strip() == (
            "graphical.target"
        )
        machine.succeed("systemctl start system-manager.target graphical.target")
        machine.wait_for_unit("gdm.service")
        active("system-manager.target")
        assert_tailscale()
        assert_manager_state(desktop=False)

    with subtest("Factory fallback and managed access survive final reboot"):
        restart_container()
        machine.wait_for_unit("graphical.target")
        machine.wait_for_unit("gdm.service")
        assert machine.succeed("systemctl get-default").strip() == (
            "graphical.target"
        )
        active("system-manager.target")
        active("gdm.service")
        assert_tailscale()
        assert_manager_state(desktop=False)
  '';
}
