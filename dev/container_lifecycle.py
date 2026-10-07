"""Explicit Docker integration test; never starts models or changes host profiles."""

import os
import signal
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUNNER = ROOT / "scripts/dev-container"
DOCKER = ["docker", "--host", "unix:///var/run/docker.sock"]


def containers():
    return set(
        subprocess.check_output(
            [*DOCKER, "ps", "-aq", "--filter", "label=sparkwerx.role=validation"], text=True
        ).split()
    )


def main():
    baseline = containers()

    def check(command, expected=0, seconds="30"):
        result = subprocess.run(
            [str(RUNNER), "bash", "-c", command],
            env={**os.environ, "SPARK_VALIDATION_SECONDS": seconds},
            timeout=45,
            check=False,
        )
        assert result.returncode == expected, (result.returncode, expected)
        assert containers() == baseline, "Validation container leaked"

    # A short-lived shell abandons each child to PID 1, reproducing the failure
    # mode of the old sleep container. Assert they are reaped before task exit.
    check(
        """
        set -euo pipefail
        git status --porcelain >/dev/null
        read -r init < /proc/1/comm
        [[ "$init" == docker-init ]]
        for i in {1..30}; do bash -c 'sleep 0.05 &'; done
        sleep 1
        for status in /proc/[0-9]*/status; do
          [[ -r "$status" ]] || continue
          while read -r key value rest; do
            if [[ "$key" == State: && "$value" == Z ]]; then
              echo "Unreaped child: $status" >&2
              exit 1
            fi
          done < "$status"
        done
        """
    )
    print("PASS: init reaped 30 orphan children; success cleanup", flush=True)
    check("exit 42", expected=42)
    print("PASS: failure status and cleanup", flush=True)
    check("sleep 60", expected=124, seconds="1")
    print("PASS: deadline and cleanup", flush=True)

    with subprocess.Popen(
        [str(RUNNER), "bash", "-c", "echo READY; sleep 60"],
        stdout=subprocess.PIPE,
        text=True,
        env={**os.environ, "SPARK_VALIDATION_SECONDS": "5"},
    ) as process:
        try:
            assert process.stdout.readline().strip() == "READY"
            process.send_signal(signal.SIGTERM)
            assert process.wait(timeout=15) == 143
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
    assert containers() == baseline, "Interrupted container leaked"
    print("PASS: interrupted runner cleanup", flush=True)


if __name__ == "__main__":
    main()
