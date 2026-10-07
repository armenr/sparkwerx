#!/usr/bin/env python3
"""Prepare private workstation bindings and an external API credential."""

import ipaddress
import json
import os
import platform
import secrets
import subprocess
from pathlib import Path


def main():
    if platform.node().split(".")[0] != "spark-9667" or os.getuid() != 1000:
        raise SystemExit("Run on spark-9667 as deadspark, without sudo")
    home = Path.home()
    if home != Path("/home/deadspark"):
        raise SystemExit("Unexpected home directory")
    devices = json.loads(
        subprocess.check_output(["ip", "-j", "address", "show", "dev", "enP7s7"], text=True)
    )
    lan = next(a["local"] for a in devices[0]["addr_info"] if a["family"] == "inet")
    tail = subprocess.check_output(["tailscale", "ip", "-4"], text=True).strip()
    if not any(
        ipaddress.ip_address(lan) in ipaddress.ip_network(n)
        for n in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
    ):
        raise SystemExit("LAN address must be RFC1918 private IPv4")
    if ipaddress.ip_address(tail) not in ipaddress.ip_network("100.64.0.0/10"):
        raise SystemExit("Expected a Tailscale IPv4 address")
    folder = home / ".config/sparkwerx/huihui-qwen38"
    for path in (home / ".config", home / ".config/sparkwerx", folder):
        if path.is_symlink():
            raise SystemExit("Refusing redirected configuration directory")
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    folder.chmod(0o700)
    api = folder / "api.env"
    network = folder / "network.env"
    if api.is_symlink() or network.is_symlink():
        raise SystemExit("Refusing redirected configuration file")
    if not api.exists():
        fd = os.open(api, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as output:
            output.write("VLLM_API_KEY=" + secrets.token_urlsafe(32) + "\n")
    api.chmod(0o600)
    desired = "SPARK_LAN_IP=" + lan + "\nSPARK_TAILSCALE_IP=" + tail + "\n"
    if network.exists() and network.read_text() != desired:
        raise SystemExit("Private addresses changed; review existing bindings before updating")
    network.write_text(desired)
    network.chmod(0o600)
    snapshot = home / (
        ".cache/huggingface/hub/models--huihui-ai--Huihui-Qwen3.8-27B-abliterated/"
        "snapshots/739e3c5b89849f6c238ce1e5b70008612ae42cdd"
    )
    index = json.loads((snapshot / "model.safetensors.index.json").read_text())
    shards = set(index["weight_map"].values())
    if not all(
        (snapshot / name).is_file() and (snapshot / name).stat().st_size > 0 for name in shards
    ):
        raise SystemExit("Model download is incomplete")
    print(f"Private bindings and external API key prepared; {len(shards)} weight shards present.")


if __name__ == "__main__":
    main()
