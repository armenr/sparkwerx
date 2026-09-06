"""Exercise the trial's actual JSON firewall transaction in private netns only."""

import importlib.util
import json
import shutil
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


control = load("trial_network_controller", "trial-control.py")
probes = load("trial_network_probes", "network-test.py")
original = probes.command
context = {"token": "0123456789ab"}


def command(*args):
    if args == ("nft", "--check", "--file", "trial-json"):
        shape = control.nft_shape(context["token"])
        batch = [{"create": shape[0]}, *({"add": item} for item in shape[1:])]
        return control.command(
            control.TOOLS["nft"],
            "--check",
            "--json",
            "--file",
            "-",
            data=json.dumps({"nftables": batch}),
        )
    if args == ("nft", "--file", "trial-json"):
        control.NETWORK.install(context)
        return ""
    return original(*args)


if __name__ == "__main__":
    # run_test itself refuses the host's initial netns before any command.
    control.TOOLS = {"nft": shutil.which("nft")}
    probes.command = command
    probes.run_test("trial-json")
    control.NETWORK.verify(context)
    control.NETWORK.remove(context)
    control.NETWORK.remove(context)
    original("nft", "list", "table", "inet", "unrelated_fixture")
    print(
        "PASS|trial_network|actual JSON transaction, rejection probes, and exact idempotent cleanup passed"
    )
