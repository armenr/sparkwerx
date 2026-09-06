"""Run the exact disposable trial lifecycle before an optional live start."""

import argparse
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("action", choices=("test", "start"))
    parser.add_argument("--preset", choices=("4k60", "1440p120", "4k120"), default="4k60")
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise ValueError("run through scripts/dgx-moonlight-trial for sudo")
    data = json.loads(args.manifest.read_text())
    spec = importlib.util.spec_from_file_location(
        "gated_trial", Path(data["source"]) / "trial-control.py"
    )
    control = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(control)
    control.TOOLS = json.loads(Path(data["tools"]).read_text()) | {"manifest": data["tools"]}
    control.BUNDLE = Path(data["bundle"])
    if not (Path(data["policy"]) / "passed").is_file():
        raise ValueError("trial package/policy checks are missing")
    if os.path.lexists(control.STATE) or os.path.lexists(control.GCROOT):
        raise ValueError("trial already has state; use status or stop")
    before = control.HOST.preflight()
    print(
        "INFO|disposable_trial_test|firewall probes, startup failure, crash cleanup, and timeout run only in a container",
        flush=True,
    )
    env = os.environ | {"NIX_USER_CONF_FILES": "/dev/null"}
    result = subprocess.run(
        [
            "/nix/var/nix/profiles/default/bin/nix",
            "--store",
            "local",
            "--extra-experimental-features",
            "nix-command flakes auto-allocate-uids cgroups",
            "--option",
            "auto-allocate-uids",
            "true",
            "build",
            "--no-link",
            data["test_drv"] + "^*",
        ],
        env=env,
        check=False,
    )
    if control.HOST.preflight() != before:
        raise RuntimeError("live host changed during the disposable test; no trial launched")
    if result.returncode:
        raise RuntimeError("disposable trial test failed; no live trial launched")
    if not Path(data["test_output"]).is_dir():
        raise RuntimeError("exact passed lifecycle output is missing")
    print(
        "PASS|trial_lifecycle|disposable lifecycle passed; live host remained unchanged", flush=True
    )
    if args.action == "start":
        executable = str(Path(data["bundle"]) / "bin/dgx-moonlight-trial")
        os.execv(executable, [executable, "start", "--preset", args.preset])


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"FAIL|moonlight_trial_gate|{error}", file=sys.stderr)
        sys.exit(1)
