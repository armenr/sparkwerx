"""Exercise only the candidate firewall in disposable Linux network namespaces."""

import json
import os
import selectors
import socket
import subprocess
import sys
import time
from pathlib import Path

TCP = (47984, 47989, 47990, 48010, 2222)
UDP = (47998, 47999, 48000)


def command(*args):
    try:
        return subprocess.run(args, check=True, text=True, capture_output=True, timeout=10).stdout
    except subprocess.CalledProcessError as error:
        raise RuntimeError(
            f"isolated command failed: {' '.join(args)}: {error.stderr.strip()}"
        ) from error


def serve():
    selector = selectors.DefaultSelector()
    for family in (socket.AF_INET, socket.AF_INET6):
        for kind, ports in ((socket.SOCK_STREAM, TCP), (socket.SOCK_DGRAM, UDP)):
            for port in ports:
                endpoint = socket.socket(family, kind)
                if family == socket.AF_INET6:
                    endpoint.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
                endpoint.bind(("0.0.0.0" if family == socket.AF_INET else "::", port))
                if kind == socket.SOCK_STREAM:
                    endpoint.listen()
                selector.register(endpoint, selectors.EVENT_READ, kind)
    print("READY", flush=True)
    while True:
        for key, _ in selector.select():
            if key.data == socket.SOCK_STREAM:
                client, _ = key.fileobj.accept()
                with client:
                    client.sendall(b"ok")
            else:
                _, address = key.fileobj.recvfrom(100)
                key.fileobj.sendto(b"ok", address)


def connect(protocol, address, port):
    family = socket.AF_INET6 if ":" in address else socket.AF_INET
    kind = socket.SOCK_DGRAM if protocol == "udp" else socket.SOCK_STREAM
    with socket.socket(family, kind) as endpoint:
        endpoint.settimeout(0.4)
        try:
            endpoint.connect((address, int(port)))
            if kind == socket.SOCK_DGRAM:
                endpoint.send(b"ping")
            return endpoint.recv(10) == b"ok"
        except (TimeoutError, ConnectionError, OSError):
            return False


def run_test(policy):
    # This executable is wrapped in unshare --net. Refuse the initial host netns
    # even if somebody invokes this Python file directly with sudo.
    if os.geteuid() != 0 or os.readlink("/proc/self/ns/net") == os.readlink("/proc/1/ns/net"):
        raise RuntimeError(
            "run the Nix test bundle as root; a private network namespace is required"
        )
    command("ip", "link", "set", "lo", "up")
    # No named netns, persistent mount, firewall operation on the host, or real
    # Tailscale peer is involved. Destroying the processes destroys these netns.
    peer = subprocess.Popen(["unshare", "--net", "sleep", "infinity"])
    server = None
    try:
        for _ in range(100):
            if os.readlink(f"/proc/{peer.pid}/ns/net") != os.readlink("/proc/self/ns/net"):
                break
            time.sleep(0.01)
        else:
            raise RuntimeError("client network namespace did not start")
        prefix = ["nsenter", "--target", str(peer.pid), "--net", "--"]
        command(*prefix, "ip", "link", "set", "lo", "up")
        # Test addresses are synthetic and never read from a real tailnet.
        networks = (
            (
                "tailscale0",
                "client-tail",
                "100.64.0.1/30",
                "100.64.0.2/30",
                "2001:db8:1::1/64",
                "2001:db8:1::2/64",
            ),
            (
                "lan0",
                "client-lan",
                "198.18.0.1/30",
                "198.18.0.2/30",
                "2001:db8:2::1/64",
                "2001:db8:2::2/64",
            ),
        )
        for local, other, local4, peer4, local6, peer6 in networks:
            command("ip", "link", "add", local, "type", "veth", "peer", "name", other)
            command("ip", "link", "set", other, "netns", str(peer.pid))
            for address in (local4, local6):
                command("ip", "address", "add", address, "dev", local, "nodad")
            command("ip", "link", "set", local, "up")
            for address in (peer4, peer6):
                command(*prefix, "ip", "address", "add", address, "dev", other, "nodad")
            command(*prefix, "ip", "link", "set", other, "up")
        command("nft", "add", "table", "inet", "unrelated_fixture")
        command(
            "nft",
            "add",
            "chain",
            "inet",
            "unrelated_fixture",
            "input",
            "{ type filter hook input priority -30; policy accept; }",
        )
        # A different base chain accepting traffic first must not bypass this
        # guard. Leave that unrelated table byte-for-byte intact.
        command("nft", "add", "rule", "inet", "unrelated_fixture", "input", "accept")
        before = json.loads(command("nft", "--json", "list", "table", "inet", "unrelated_fixture"))
        command("nft", "--check", "--file", policy)
        command("nft", "--file", policy)
        server = subprocess.Popen(
            [sys.executable, __file__, "--serve"], text=True, stdout=subprocess.PIPE
        )
        with selectors.DefaultSelector() as readiness:
            readiness.register(server.stdout, selectors.EVENT_READ)
            if not readiness.select(timeout=5):
                raise RuntimeError("fixture listener startup timed out")
        if server.stdout.readline().strip() != "READY":
            raise RuntimeError("fixture listener failed")

        count = 0
        for interface, _, addr4, _, addr6, _ in networks:
            for address in (addr4.split("/")[0], addr6.split("/")[0]):
                for protocol, ports in (("tcp", TCP), ("udp", UDP)):
                    for port in ports:
                        expected = port == 2222 or (interface == "tailscale0" and port != 47990)
                        probe = subprocess.run(
                            prefix
                            + [sys.executable, __file__, "--connect", protocol, address, str(port)],
                            check=False,
                            timeout=5,
                        )
                        if (probe.returncode == 0) != expected:
                            raise RuntimeError(
                                f"{interface}/{protocol}/{port}: expected reachable={expected}"
                            )
                        count += 1
        for address in ("127.0.0.1", "::1", "100.64.0.1"):
            if not connect("tcp", address, 47990):
                raise RuntimeError("local administration/SSH-forward path was blocked")
        after = json.loads(command("nft", "--json", "list", "table", "inet", "unrelated_fixture"))
        if before != after:
            raise RuntimeError("unrelated firewall table changed")
        print(
            f"PASS|remote_desktop_network|{count} IPv4/IPv6 TCP/UDP probes; admin forwarding and unrelated table preserved"
        )
    finally:
        for process in (server, peer):
            if process:
                process.terminate()
                process.wait(timeout=5)


if __name__ == "__main__":
    if sys.argv[1:] == ["--serve"]:
        serve()
    elif sys.argv[1:2] == ["--connect"]:
        raise SystemExit(0 if connect(*sys.argv[2:]) else 1)
    else:
        run_test(str(Path(sys.argv[1]).resolve()))
