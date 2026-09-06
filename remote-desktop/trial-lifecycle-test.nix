{
  system-manager,
  pkgs,
  rootCanary,
  trial,
}:
system-manager.lib.containerTest.makeContainerTest {
  hostPkgs = pkgs;
  name = "dgx-moonlight-trial-lifecycle";
  toplevel = rootCanary;
  extraPathsToRegister = [
    trial.fixture
    trial.networkTest
  ];
  testScript = ''
    import json

    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("hostname moonlight-trial-fixture")
    machine.succeed("systemd-run --unit=trial-sentinel /usr/bin/sleep infinity")
    operator = "${trial.fixture}/bin/dgx-moonlight-trial"
    nft = "${pkgs.nftables}/bin/nft"
    guard = "sparkwerx-moonlight-trial.service"
    worker = "sparkwerx-moonlight-session.service"
    state = "/run/sparkwerx-moonlight-trial"
    root = "/nix/var/nix/gcroots/sparkwerx-moonlight-trial"

    def stopped() -> None:
        machine.wait_until_succeeds(f"test ! -e '{state}'", timeout=45)
        machine.succeed(f"{operator} status | grep -Fx TRIAL_STATUS=STOPPED")
        machine.fail(f"test -e '{root}' || test -L '{root}'")
        machine.fail(f"systemctl is-active --quiet {worker}")
        machine.fail(f"{nft} list table inet sparkwerx_sunshine")
        machine.succeed(f"{nft} list table inet unrelated_trial_fixture")
        machine.succeed("systemctl is-active --quiet trial-sentinel.service")

    def ready() -> str:
        machine.succeed(f"{operator} start")
        machine.wait_until_succeeds(f"{operator} status | grep -Fx TRIAL_STATUS=READY_FOR_PAIRING", timeout=15)
        data = json.loads(machine.succeed(f"cat {state}/context.json"))
        return str(data["snapshot"])

    with subtest("Actual JSON network guard rejects LAN and IPv6 admin access"):
        machine.succeed("${trial.networkTest}/bin/sparkwerx-moonlight-trial-network-test")

    machine.succeed("ip link add tailscale0 type dummy")
    machine.succeed("ip address add 100.64.0.1/32 dev tailscale0")
    machine.succeed("ip link set tailscale0 up")
    machine.succeed(f"{nft} add table inet unrelated_trial_fixture")

    with subtest("An occupied table is preserved without starting a session"):
        machine.succeed(f"{nft} add table inet sparkwerx_sunshine")
        machine.fail(f"{operator} start")
        machine.succeed(f"{nft} list table inet sparkwerx_sunshine")
        machine.fail(f"test -e {state}")
        machine.succeed(f"{nft} delete table inet sparkwerx_sunshine")

    with subtest("Manual stop kills the whole worker and restores the exact boundary"):
        snapshot = ready()
        child_pid = machine.succeed(f"cat {snapshot}/fixture-child.pid").strip()
        machine.fail(f"{operator} start")
        machine.succeed(f"{operator} stop")
        stopped()
        machine.wait_until_succeeds(f"! kill -0 {child_pid}", timeout=5)
        machine.succeed(f"test -f {snapshot}/finished.json")
        machine.succeed(f"{operator} stop")

    with subtest("A dead guardian still stops listeners before removing its rules"):
        ready()
        machine.succeed(f"systemctl kill --signal=SIGKILL --kill-whom=main {guard}")
        stopped()

    with subtest("Worker startup failure performs the same cleanup"):
        machine.succeed("printf worker-failure > /run/trial-fixture-mode")
        machine.succeed(f"{operator} start")
        stopped()
        machine.succeed("unlink /run/trial-fixture-mode")

    with subtest("The hard deadline stops a disconnected unconfirmed trial"):
        ready()
        machine.succeed(f"systemctl kill --signal=SIGSTOP --kill-whom=main {guard}")
        stopped()

    with subtest("Access loss stops graphics and preserves evidence until health returns"):
        ready()
        machine.succeed("printf access-loss > /run/trial-fixture-mode")
        machine.wait_until_succeeds(f"test $(systemctl show {worker} -p ActiveState --value) = inactive", timeout=20)
        machine.succeed(f"test -f {state}/context.json")
        machine.fail(f"{nft} list table inet sparkwerx_sunshine")
        machine.succeed("unlink /run/trial-fixture-mode")
        machine.succeed(f"{operator} stop")
        stopped()

    with subtest("Changed firewall rules stop the worker but are not deleted"):
        ready()
        machine.succeed(f"{nft} add rule inet sparkwerx_sunshine input counter")
        machine.wait_until_succeeds(f"test $(systemctl show {worker} -p ActiveState --value) = inactive", timeout=20)
        machine.succeed(f"test -f {state}/context.json")
        machine.succeed(f"{nft} list table inet sparkwerx_sunshine")
        machine.fail(f"{operator} stop")
        rules = json.loads(machine.succeed(f"{nft} --json list table inet sparkwerx_sunshine"))["nftables"]
        handle = [item["rule"]["handle"] for item in rules if "rule" in item][-1]
        machine.succeed(f"{nft} delete rule inet sparkwerx_sunshine input handle {handle}")
        machine.succeed(f"{operator} stop")
        stopped()
  '';
}
