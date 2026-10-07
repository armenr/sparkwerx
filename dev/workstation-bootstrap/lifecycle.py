"""Native Ubuntu/systemd test of the workstation's official Nix bootstrap."""

import hashlib
import json
import os
import subprocess
import time
from pathlib import Path

REPO = Path("/home/deadspark/Development/DGX-setup")
ADAPTER = REPO / "workstations/bootstrap"


def run(*args, ok=True, env=None):
    result = subprocess.run(
        args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env
    )
    print(result.stdout, end="", flush=True)
    if ok and result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {args}")
    return result


def snapshot():
    return {
        str(path): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in (
            Path("/nix/receipt.json"),
            Path("/nix/nix-installer"),
            Path("/etc/nix/nix.conf"),
        )
    } | {"profile": str(Path("/nix/var/nix/profiles/default").resolve())}


def main():
    if not Path("/.dockerenv").exists() or os.geteuid() != 0:
        raise SystemExit("Disposable root container only")
    assert not Path("/nix").exists()
    assert run("uname", "-m").stdout.strip() == "aarch64"
    assert run("hostname", "-s").stdout.strip() == "spark-9667"
    assert run("systemctl", "is-system-running", "--wait").stdout.strip() == "running"

    # Synthetic protected services/GPU prove preservation, not hardware behavior.
    for name in (
        "gdm",
        "docker",
        "dgx-dashboard",
        "dgx-dashboard-admin",
        "nvidia-persistenced",
        "tailscaled",
    ):
        Path(f"/etc/systemd/system/{name}.service").write_text(
            "[Service]\nExecStart=/usr/bin/sleep infinity\n"
        )
    gpu = Path("/usr/local/bin/nvidia-smi")
    gpu.write_text("#!/bin/sh\nprintf '%s\\n' 'NVIDIA GB10, 580.178.04'\n")
    gpu.chmod(0o755)
    tailscale = Path("/usr/local/bin/tailscale")
    tailscale.write_text(
        "#!/usr/bin/python3\nimport json,sys\nfrom pathlib import Path\n"
        'if sys.argv[1] == "status":\n'
        ' print(json.dumps({"BackendState":"Running","Self":{"Online":not Path("/test-offline").exists()}}))\n'
        'elif sys.argv[1:] == ["debug","prefs"]:\n'
        ' print(json.dumps({"WantRunning":True,"RunSSH":False}))\n'
        "else: sys.exit(1)\n"
    )
    tailscale.chmod(0o755)
    run("systemctl", "daemon-reload")
    run(
        "systemctl",
        "start",
        "gdm",
        "docker",
        "dgx-dashboard",
        "dgx-dashboard-admin",
        "nvidia-persistenced",
        "tailscaled",
    )
    commit = run(
        "git", "-c", f"safe.directory={REPO}", "-C", str(REPO), "rev-parse", "HEAD"
    ).stdout.strip()
    command = [
        str(ADAPTER / "scripts/bootstrap-nix.sh"),
        "spark-9667",
        "--root-install",
        commit,
        "deadspark",
    ]
    sudo = ["runuser", "-u", "deadspark", "--", "sudo", "-n", "env"]
    offline = Path("/test-offline")
    offline.touch()
    refused = run(*sudo, *command, ok=False)
    assert refused.returncode and "not healthy before bootstrap" in refused.stdout
    assert not Path("/nix").exists()
    offline.unlink()
    time.sleep(1.1)
    print("PASS: offline Tailscale is refused before Nix installation", flush=True)
    failed = run(*sudo, "DGX_NIX_BOOTSTRAP_TEST_FAIL_AFTER_RUNTIME=1", *command, ok=False)
    assert failed.returncode and "injected post-runtime failure" in failed.stdout
    evidence = sorted(Path("/var/lib/dgx-setup/nix-bootstrap").iterdir())[-1]
    assert (evidence / "ARMED").exists()
    stamp = evidence.name
    timer = f"dgx-nix-bootstrap-rollback-{stamp}.timer"
    service = f"dgx-nix-bootstrap-rollback-{stamp}.service"
    run("systemctl", "is-active", "--quiet", timer)
    # Trigger the same systemd service the timer would invoke; retain its timer
    # until receipt-driven rollback has proven complete.
    run("systemctl", "start", service)
    deadline = time.monotonic() + 90
    while not (evidence / "ROLLED_BACK").exists() and time.monotonic() < deadline:
        time.sleep(0.2)
    assert (evidence / "ROLLED_BACK").exists()
    assert not Path("/nix").exists() and not Path("/etc/nix").exists()
    run("systemctl", "stop", timer)
    print("PASS: injected failure and systemd-driven receipt rollback", flush=True)
    time.sleep(1.1)  # Bootstrap evidence names have one-second resolution.

    success = run(*sudo, *command)
    assert "BOOTSTRAP_STATUS=INSTALLED" in success.stdout
    assert "2.35.2" in run("/nix/var/nix/profiles/default/bin/nix", "--version").stdout
    before = snapshot()
    adopted = run(
        "runuser",
        "-u",
        "deadspark",
        "--",
        "env",
        "HOME=/home/deadspark",
        str(ADAPTER / "scripts/bootstrap-nix.sh"),
        "spark-9667",
    )
    assert "BOOTSTRAP_STATUS=ADOPTED" in adopted.stdout
    assert snapshot() == before
    assert run("systemctl", "is-system-running").stdout.strip() == "running"
    receipt = json.loads(Path("/nix/receipt.json").read_text())
    assert receipt["version"] == "2.35.2"
    print(
        "PASS: clean reinstall, runtime, disarmed recovery, and idempotent user adoption",
        flush=True,
    )


if __name__ == "__main__":
    main()
