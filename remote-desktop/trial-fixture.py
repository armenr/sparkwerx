"""Container-only stand-in for GPU/access checks; the guardian is production code.

Not shipped in the live operator bundle. No fixture switch exists in that bundle.
"""

import importlib.util
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("trial_fixture_control", HERE / "trial-control.py")
control = importlib.util.module_from_spec(spec)
spec.loader.exec_module(control)
MODE = Path("/run/trial-fixture-mode")


def container_only():
    if (
        os.geteuid() != 0
        or socket.gethostname() != "moonlight-trial-fixture"
        or subprocess.run(
            ["/usr/bin/systemd-detect-virt", "--container", "--quiet"], check=False
        ).returncode
        or any(Path("/dev").glob("nvidia*"))
    ):
        raise RuntimeError(
            "fixture may run only inside its disposable container without GPU devices"
        )


class FixtureHost(control.Host):
    def preflight(self):
        return self.snapshot()

    def snapshot(self):
        if MODE.exists() and MODE.read_text() == "access-loss":
            raise RuntimeError("injected access loss")
        value = control.command(
            "/usr/bin/systemctl",
            "show",
            "trial-sentinel.service",
            "-p",
            "MainPID",
            "-p",
            "ActiveState",
        )
        if "ActiveState=active" not in value:
            raise RuntimeError("fixture sentinel changed")
        return {"tailscale_address": "100.64.0.1", "gpu": "fixture, 580.173.02", "sentinel": value}

    def worker_properties(self, context):
        # Same lifetime, dependency/stop ordering, and guardian. The container
        # substitutes an echo server for GPU code; it never has a host GPU bind.
        return {
            "Description": control.description(context["token"], "session"),
            "Type": "exec",
            "RuntimeMaxSec": "26s",
            "TimeoutStopSec": "2s",
            "KillMode": "control-group",
            "BindsTo": control.GUARD,
            "After": control.GUARD,
            "StandardOutput": "append:" + str(Path(context["snapshot"]) / "fixture.log"),
            "StandardError": "inherit",
        }, ()

    def session(self, action):
        if action != "worker":
            raise ValueError("fixture only replaces the GPU worker")
        sockets = []
        try:
            if MODE.exists() and MODE.read_text() == "worker-failure":
                raise RuntimeError("injected worker failure")
            for kind, ports in (
                (socket.SOCK_STREAM, control.TCP),
                (socket.SOCK_DGRAM, control.UDP),
            ):
                for port in ports:
                    endpoint = socket.socket(socket.AF_INET, kind)
                    endpoint.bind(("100.64.0.1", port))
                    if kind == socket.SOCK_STREAM:
                        endpoint.listen()
                    sockets.append(endpoint)
            # A separate child must also disappear when the worker is killed.
            child = subprocess.Popen(["/usr/bin/sleep", "infinity"])
            context = control.context_read()
            (Path(context["snapshot"]) / "fixture-child.pid").write_text(str(child.pid))
            control.save_json(control.STATE / "result/ready.json", {"ready": True})
            while True:
                time.sleep(1)
        finally:
            for endpoint in sockets:
                endpoint.close()


if __name__ == "__main__":
    try:
        container_only()
        control.HISTORY = Path("/var/lib/trial-fixture-history")
        control.LIMIT = 30
        control.SHUTDOWN_MARGIN = 5
        control.HOST = FixtureHost()
        control.main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"FAIL|trial_fixture|{error}", file=sys.stderr)
        sys.exit(1)
