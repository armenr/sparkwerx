"""Exercise the trial's actual JSON firewall transaction in private netns only."""

import importlib.util
import json
import os
import shutil
import subprocess
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


def isolated_nft(*args, data=None, timeout=15):
    # Unlike the live controller, this fixture contains no host addresses or
    # authentication. Preserve nft's actual error, but only in a private netns
    # and only for the pinned firewall tool. Never expose live command output.
    if (
        os.geteuid() != 0
        or os.readlink("/proc/self/ns/net") == os.readlink("/proc/1/ns/net")
        or not args
        or str(args[0]) != control.TOOLS["nft"]
    ):
        raise RuntimeError("firewall diagnostics require the isolated network fixture")
    result = subprocess.run(args, input=data, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(
            f"isolated nft failed (exit {result.returncode}): {result.stderr.strip()}"
        )
    return result.stdout.strip()


def command(*args):
    if args == ("nft", "--check", "--file", "trial-json"):
        return control.command(
            control.TOOLS["nft"],
            "--check",
            "--json",
            "--file",
            "-",
            data=json.dumps(control.nft_batch(context["token"])),
        )
    if args == ("nft", "--file", "trial-json"):
        control.NETWORK.install(context)
        return ""
    return original(*args)


if __name__ == "__main__":
    # run_test itself refuses the host's initial netns before any command.
    control.TOOLS = {"nft": shutil.which("nft")}
    control.command = isolated_nft
    probes.command = command
    probes.run_test("trial-json")
    control.NETWORK.verify(context)
    control.NETWORK.remove(context)
    control.NETWORK.remove(context)
    original("nft", "list", "table", "inet", "unrelated_fixture")
    print(
        "PASS|trial_network|actual JSON transaction, rejection probes, and exact idempotent cleanup passed"
    )
