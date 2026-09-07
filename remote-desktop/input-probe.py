"""Private Wayland input receipt plus the normal offline Sunshine startup probe.

Selected only by its separate Nix bundle; the passed offline outputs stay exact.
TCP/UDP and kernel input devices remain denied throughout this diagnostic.
"""

import importlib.util
import subprocess
import time
from pathlib import Path

original = (
    "sunshine-startup.py" if Path(__file__).name == "input-probe.py" else "sunshine-original.py"
)
spec = importlib.util.spec_from_file_location(
    "original_startup", Path(__file__).with_name(original)
)
startup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(startup)
RECEIPT = "PASS|private_input_receipt|keys=6;lower=1;upper=1;buttons=4;axes=2;motion=yes"


def expected_report(preset, version, output):
    return startup.expected_report(preset, version, output) | {
        "private_wayland_input_tested": True,
        "kernel_input_access": False,
    }


def probe(tools, preset, output, env, stop, verify_isolation):
    startup.probe(tools, preset, output, env, stop, verify_isolation)
    log = startup.read_log(Path(env["HOME"]) / "sunshine-startup/console.log")
    if "Sparkwerx session-local Wayland keyboard/pointer ready" not in log:
        raise RuntimeError("Sunshine did not initialize the private Wayland input adapter")
    verify_isolation()
    path = Path(env["HOME"]) / "input-receipt.log"
    receiver = None
    try:
        with path.open("wb") as stream:
            receiver = subprocess.Popen(
                [tools["inputReceiver"]],
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=stream,
                stderr=subprocess.STDOUT,
            )
            deadline = time.monotonic() + 5
            while "READY\n" not in startup.read_log(path):
                if receiver.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError("private input receiver did not become ready")
                time.sleep(0.05)
            subprocess.run(
                [tools["inputExercise"], "--exercise"],
                env=env,
                stdin=subprocess.DEVNULL,
                check=True,
                timeout=10,
            )
            if receiver.wait(timeout=5) != 0 or RECEIPT not in startup.read_log(path):
                raise RuntimeError("private keyboard/pointer receipt did not match")
    finally:
        stop(receiver)
        if path.exists():
            # This synthetic-input transcript contains counts only and stays
            # inside the root-private session log.
            print(startup.read_log(path), flush=True)
    verify_isolation()
    return expected_report(preset, tools["sunshineVersion"], output)
