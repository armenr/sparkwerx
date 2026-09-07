"""Temporary Moonlight trial controller. No profile, desktop-mode, or boot changes."""

import argparse
import hashlib
import importlib.util
import ipaddress
import json
import os
import re
import signal
import socket
import stat
import subprocess
import sys
import time
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
STATE = Path("/run/sparkwerx-moonlight-trial")
GCROOT = Path("/nix/var/nix/gcroots/sparkwerx-moonlight-trial")
REPO = Path("/home/n0b0dy/Development/DGX-setup")
HISTORY = REPO / "inventory/sparkle-01/raw/moonlight-trial"
GUARD = "sparkwerx-moonlight-trial.service"
WORKER = "sparkwerx-moonlight-session.service"
TABLE = "sparkwerx_sunshine"
LIMIT = 1800
SHUTDOWN_MARGIN = 15
TCP = (47984, 47989, 47990, 48010)
UDP = (47998, 47999, 48000)
TOOLS = {}
BUNDLE = None


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


capture = module("moonlight_capture_helpers", "session-test.py")


def command(*args, data=None, timeout=15):
    # Never print captured command output here: address and auth details stay
    # in root-private evidence, not exceptions or the operator's terminal.
    result = subprocess.run(
        [str(arg) for arg in args], input=data, capture_output=True, text=True, timeout=timeout
    )
    if result.returncode:
        raise RuntimeError(f"{Path(str(args[0])).name} failed (exit {result.returncode})")
    return result.stdout.strip()


def read_json(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd) as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_size > 256 * 1024:
            raise ValueError("expected small root-owned trial metadata")
        return json.load(stream)


def save_json(path, value):
    temporary = path.with_name(path.name + ".new")
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as stream:
        json.dump(value, stream, indent=2)
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)


def private_directory(path, *, create=False):
    for ancestor in (path, *path.parents):
        if ancestor.is_symlink():
            raise ValueError("trial metadata has a symlink ancestor")
    if create:
        path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.stat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError("trial metadata directory must be root-owned mode 0700")


def description(token, role):
    return f"Sparkwerx Moonlight {role} {token}"


def unit_info(unit):
    result = command(
        "/usr/bin/systemctl",
        "show",
        unit,
        "-p",
        "Id",
        "-p",
        "LoadState",
        "-p",
        "ActiveState",
        "-p",
        "Description",
    )
    return dict(line.split("=", 1) for line in result.splitlines() if "=" in line)


def own_unit(unit, context):
    value = unit_info(unit)
    role = "guardian" if unit == GUARD else "session"
    if value.get("LoadState") != "not-found" and value.get("Description") != description(
        context["token"], role
    ):
        raise RuntimeError("trial unit name is occupied by a different unit")
    return value


def nft_shape(token):
    table = {"family": "inet", "name": TABLE, "comment": "sparkwerx-trial-" + token}
    chain = {
        "family": "inet",
        "table": TABLE,
        "name": "input",
        "type": "filter",
        "hook": "input",
        "prio": -20,
        "policy": "accept",
    }
    objects = [{"table": table}, {"chain": chain}]
    for protocol, ports, interfaces in (
        ("tcp", 47990, "lo"),
        ("tcp", {"set": [47984, 47989, 48010]}, {"set": ["lo", "tailscale0"]}),
        ("udp", {"set": list(UDP)}, {"set": ["lo", "tailscale0"]}),
    ):
        objects.append(
            {
                "rule": {
                    "family": "inet",
                    "table": TABLE,
                    "chain": "input",
                    "expr": [
                        {
                            "match": {
                                "op": "!=",
                                "left": {"meta": {"key": "iifname"}},
                                "right": interfaces,
                            }
                        },
                        {
                            "match": {
                                "op": "==",
                                "left": {"payload": {"protocol": protocol, "field": "dport"}},
                                "right": ports,
                            }
                        },
                        # nftables 1.1.6 treats an empty object as an invalid
                        # named-counter reference. Initialize anonymous counters
                        # explicitly; kernel readback uses this same shape.
                        {"counter": {"packets": 0, "bytes": 0}},
                        {"drop": None},
                    ],
                }
            }
        )
    return objects


def nft_batch(token):
    shape = nft_shape(token)
    return {"nftables": [{"create": shape[0]}, *({"add": item} for item in shape[1:])]}


def canonical(value):
    if isinstance(value, list):
        return [
            canonical(item)
            for item in value
            if not isinstance(item, dict) or "metainfo" not in item
        ]
    if isinstance(value, dict):
        counter = value.get("counter")
        if (
            set(value) == {"counter"}
            and isinstance(counter, dict)
            and set(counter) == {"packets", "bytes"}
            and all(type(number) is int and number >= 0 for number in counter.values())
        ):
            return {"counter": {"packets": 0, "bytes": 0}}
        return {key: canonical(item) for key, item in value.items() if key != "handle"}
    return value


class Network:
    def current(self):
        # Listing tables must succeed; a permission/tool error is not absence.
        tables = json.loads(command(TOOLS["nft"], "--json", "list", "tables"))["nftables"]
        if not any(
            item.get("table", {}).get("family") == "inet" and item["table"].get("name") == TABLE
            for item in tables
        ):
            return None
        data = json.loads(command(TOOLS["nft"], "--json", "list", "table", "inet", TABLE))
        return canonical(data["nftables"])

    def verify(self, context):
        if self.current() != nft_shape(context["token"]):
            raise RuntimeError("the trial network guard is absent or changed")

    def install(self, context):
        if self.current() is not None:
            raise RuntimeError("the trial firewall table already exists")
        # One atomic batch, with exclusive creation. A racing table creation
        # aborts the batch rather than appending rules to somebody else's table.
        command(TOOLS["nft"], "--json", "--file", "-", data=json.dumps(nft_batch(context["token"])))
        self.verify(context)

    def remove(self, context):
        if self.current() is None:
            return
        self.verify(context)
        command(TOOLS["nft"], "delete", "table", "inet", TABLE)
        if self.current() is not None:
            raise RuntimeError("trial firewall table remains after cleanup")


NETWORK = Network()


def tailscale_address():
    status = json.loads(command("/usr/bin/tailscale", "status", "--json"))
    prefs = json.loads(command("/usr/bin/tailscale", "debug", "prefs"))
    peer = status.get("Self", {})
    addresses = [
        str(ipaddress.ip_address(value))
        for value in peer.get("TailscaleIPs", [])
        if ipaddress.ip_address(value).version == 4
    ]
    if (
        status.get("BackendState") != "Running"
        or peer.get("Online") is not True
        or prefs.get("WantRunning") is not True
        or prefs.get("RunSSH") is not True
        or len(addresses) != 1
        or ipaddress.ip_address(addresses[0]) not in ipaddress.ip_network("100.64.0.0/10")
    ):
        raise RuntimeError("Tailscale address/access prerequisites failed")
    links = json.loads(command("/usr/sbin/ip", "-j", "address", "show", "dev", "tailscale0"))
    if len(links) != 1 or addresses[0] not in [
        item.get("local") for item in links[0].get("addr_info", [])
    ]:
        raise RuntimeError("the selected address is not on tailscale0")
    return addresses[0], hashlib.sha256(str(peer["ID"]).encode()).hexdigest()


def health_snapshot():
    # Like the passed capture snapshot, but permit only our own transient units
    # to be finishing a failed run. Never relax a protected service's record.
    failed = json.loads(
        command("/usr/bin/systemctl", "list-units", "--failed", "--output=json", "--no-pager")
    )
    if any(item["unit"] not in (GUARD, WORKER) for item in failed):
        raise RuntimeError("an unrelated systemd unit is failed")
    address, identity = tailscale_address()
    value = {
        "units_profile": capture.gpu.host_snapshot(),
        "devices": capture.device_snapshot(),
        "boot": Path("/proc/sys/kernel/random/boot_id").read_text(),
        "files": {
            name: hashlib.sha256(Path(name).read_bytes()).hexdigest()
            for name in (
                "/etc/passwd",
                "/etc/group",
                "/etc/nix/nix.conf",
                "/var/lib/system-manager/state/system-manager-state.json",
            )
        },
        "gpu": command(
            "/usr/bin/nvidia-smi", "--query-gpu=name,driver_version", "--format=csv,noheader"
        ),
        "tailscale_address": address,
        "tailscale_identity": identity,
    }
    return json.loads(json.dumps(value))


class Host:
    def preflight(self):
        capture.preflight(sunshine=True)
        return health_snapshot()

    def snapshot(self):
        return health_snapshot()

    def worker_properties(self, context):
        properties = capture.unit_properties(STATE / "result", sunshine=True)
        properties.update(
            {
                "Description": description(context["token"], "session"),
                "RuntimeMaxSec": str(context["limit"] - 10) + "s",
                "PrivateNetwork": "no",
                "RestrictAddressFamilies": "AF_UNIX AF_NETLINK AF_INET AF_INET6",
                "BindsTo": GUARD,
                "After": GUARD,
                "StandardOutput": "append:" + str(Path(context["snapshot"]) / "session.log"),
                "StandardError": "inherit",
            }
        )
        return properties, capture.device_nodes(sunshine=True)

    def session(self, action):
        session = module("moonlight_trial_session", "trial-session.py")
        session.run(action, TOOLS, BUNDLE)


HOST = Host()


def context_read():
    private_directory(STATE)
    value = read_json(STATE / "context.json")
    if (
        not re.fullmatch(r"[a-f0-9]{12}", value.get("token", ""))
        or value.get("bundle") != str(BUNDLE)
        or value.get("tools") != TOOLS["manifest"]
        or value.get("limit") != LIMIT
    ):
        raise ValueError("trial context does not match the retained program")
    snapshot = Path(value["snapshot"])
    if snapshot.parent != HISTORY or not re.fullmatch(r"\d{8}T\d{6}Z-[a-f0-9]{12}", snapshot.name):
        raise ValueError("unexpected trial snapshot path")
    private_directory(snapshot)
    if read_json(snapshot / "context.json") != value:
        raise ValueError("trial context differs from its snapshot")
    if not GCROOT.is_symlink() or GCROOT.resolve() != BUNDLE:
        raise ValueError("trial code retention is missing or changed")
    return value


def internal_command(action):
    return [
        sys.executable,
        "-B",
        str(HERE / TOOLS.get("controller", "trial-control.py")),
        "--tools",
        TOOLS["manifest"],
        "--bundle",
        str(BUNDLE),
        action,
    ]


def launch_unit(unit, properties, argv, devices=()):
    args = ["/usr/bin/systemd-run", "--quiet", "--collect", f"--unit={unit}"]
    args += [f"--property={key}={value}" for key, value in properties.items()]
    args += [f"--property=DeviceAllow={device} rw" for device in devices]
    command(*args, *argv)


def assert_ports_free():
    for table in ("tcp", "tcp6", "udp", "udp6"):
        ports = TCP if table.startswith("tcp") else UDP
        for line in Path("/proc/net/" + table).read_text().splitlines()[1:]:
            # TIME_WAIT is not a listener and survives a correctly stopped
            # server. UDP has no listen operation: every bound socket counts.
            if table.startswith("tcp") and line.split()[3] != "0A":
                continue
            if int(line.split()[1].rsplit(":", 1)[1], 16) in ports:
                raise RuntimeError("a trial port is already occupied")


def cleanup():
    if not STATE.exists():
        return
    context = context_read()
    info = own_unit(WORKER, context)
    if info.get("LoadState") != "not-found":
        command("/usr/bin/systemctl", "stop", WORKER, timeout=20)
    if own_unit(WORKER, context).get("ActiveState") not in ("inactive", "failed"):
        raise RuntimeError("session still running; network guard retained")
    # This ordering also applies after SIGKILL, startup failure, and timeout.
    # A modified firewall table is evidence to inspect, never something to flush.
    assert_ports_free()
    NETWORK.remove(context)
    after = HOST.snapshot()
    snapshot = Path(context["snapshot"])
    save_json(snapshot / "after.json", after)
    if after != read_json(snapshot / "before.json"):
        raise RuntimeError("host postflight differs; evidence and retention kept")
    save_json(
        snapshot / "finished.json",
        {
            "host_unchanged": True,
            "listeners_stopped": True,
            "network_guard_removed": True,
            "finished_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        },
    )
    # Only our known ephemeral metadata is removed; snapshots are retained.
    for name in ("ready.json", "ready.json.new", "context.json"):
        (STATE / "result" / name).unlink(missing_ok=True)
    (STATE / "result").rmdir()
    (STATE / "context.json").unlink()
    STATE.rmdir()
    GCROOT.unlink()
    print(
        "PASS|trial_cleanup|session/listeners stopped; own firewall and temporary root removed; host unchanged",
        flush=True,
    )


def start(preset):
    if os.path.lexists(STATE) or os.path.lexists(GCROOT):
        raise RuntimeError("trial state already exists; use status or stop")
    for unit in (GUARD, WORKER):
        if unit_info(unit).get("LoadState") != "not-found":
            raise RuntimeError("a trial unit already exists")
    if NETWORK.current() is not None:
        raise RuntimeError("the trial firewall table already exists")
    assert_ports_free()
    before = HOST.preflight()
    private_directory(HISTORY, create=True)
    token = uuid.uuid4().hex[:12]
    snapshot = HISTORY / (time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()) + "-" + token)
    snapshot.mkdir(mode=0o700)
    context = {
        "token": token,
        "snapshot": str(snapshot),
        "bundle": str(BUNDLE),
        "tools": TOOLS["manifest"],
        "preset": preset,
        "limit": LIMIT,
        "started": time.monotonic(),
        "address": before["tailscale_address"],
        "driver": before["gpu"].rsplit(", ", 1)[1],
    }
    save_json(snapshot / "before.json", before)
    save_json(snapshot / "context.json", context)
    # Precreate private logs; do not depend on systemd's file-creation mode.
    for name in ("guardian.log", "session.log"):
        fd = os.open(snapshot / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        os.close(fd)
    STATE.mkdir(mode=0o700)
    (STATE / "result").mkdir(mode=0o700)
    save_json(STATE / "context.json", context)
    save_json(STATE / "result/context.json", context)
    GCROOT.symlink_to(BUNDLE)
    properties = {
        "Description": description(token, "guardian"),
        "Type": "exec",
        "RuntimeMaxSec": f"{LIMIT}s",
        "TimeoutStopSec": "30s",
        "Restart": "no",
        "KillMode": "control-group",
        "UMask": "0077",
        "Environment": "PATH=/usr/bin:/bin LANG=C.UTF-8",
        "LimitCORE": "0",
        "StandardOutput": "append:" + str(snapshot / "guardian.log"),
        "StandardError": "inherit",
        "ExecStopPost": " ".join(internal_command("cleanup")),
    }
    try:
        if HOST.preflight() != before:
            raise RuntimeError("host changed while preparing the trial")
        launch_unit(GUARD, properties, internal_command("guardian"))
    except BaseException:
        if own_unit(GUARD, context).get("ActiveState") in ("active", "activating", "deactivating"):
            command("/usr/bin/systemctl", "stop", GUARD, timeout=35)
        else:
            cleanup()
        raise
    print("TRIAL_STATUS=STARTING", flush=True)
    print(f"PRIVATE_EVIDENCE={snapshot}", flush=True)
    print(
        "30-minute maximum; no reboot, normal desktop switch, physical input, or audio.", flush=True
    )


def guardian():
    if not re.search(rf"/{re.escape(GUARD)}(?:/|$)", Path("/proc/self/cgroup").read_text()):
        raise RuntimeError("guardian must run inside its own transient service")
    context = context_read()
    with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as lock:
        lock.bind("\0sparkwerx-private-capture-test")
        if HOST.preflight() != read_json(Path(context["snapshot"]) / "before.json"):
            raise RuntimeError("host changed before trial start")
        NETWORK.install(context)
        properties, devices = HOST.worker_properties(context)
        launch_unit(WORKER, properties, internal_command("worker"), devices)
        next_health = 0.0
        while time.monotonic() < context["started"] + LIMIT - SHUTDOWN_MARGIN:
            NETWORK.verify(context)
            if own_unit(WORKER, context).get("ActiveState") not in ("active", "activating"):
                raise RuntimeError("temporary session exited")
            if time.monotonic() >= next_health:
                if HOST.snapshot() != read_json(Path(context["snapshot"]) / "before.json"):
                    raise RuntimeError("protected host/access state changed during trial")
                next_health = time.monotonic() + 5
            time.sleep(0.5)
    # ExecStopPost owns all cleanup, including failure and forced termination.


def status():
    if not STATE.exists():
        if os.path.lexists(GCROOT) or NETWORK.current() is not None:
            raise RuntimeError("orphaned trial surface remains; inspect before starting")
        print("TRIAL_STATUS=STOPPED")
        return
    context = context_read()
    active = own_unit(GUARD, context).get("ActiveState")
    worker = own_unit(WORKER, context).get("ActiveState")
    if active not in ("active", "activating"):
        print("TRIAL_STATUS=CLEANUP_PENDING")
        return
    if (
        NETWORK.current() is None
        and worker == "inactive"
        and time.monotonic() < context["started"] + 10
    ):
        print("TRIAL_STATUS=STARTING")
        return
    NETWORK.verify(context)
    if HOST.snapshot() != read_json(Path(context["snapshot"]) / "before.json"):
        raise RuntimeError("protected host/access state differs")
    ready = STATE / "result/ready.json"
    if worker == "active" and ready.exists() and read_json(ready) == {"ready": True}:
        print("TRIAL_STATUS=READY_FOR_PAIRING")
    else:
        print("TRIAL_STATUS=STARTING")
    print(
        "SECONDS_REMAINING="
        + str(max(0, int(context["started"] + LIMIT - SHUTDOWN_MARGIN - time.monotonic())))
    )


def stop():
    if not STATE.exists():
        status()
        return
    context = context_read()
    if own_unit(GUARD, context).get("ActiveState") in ("active", "activating", "deactivating"):
        command("/usr/bin/systemctl", "stop", GUARD, timeout=35)
    if STATE.exists():
        cleanup()
    status()


def without_pairing_details(log):
    # The reused offline inspector never had pairing traffic. An online trial
    # needs this extra exclusion before its existing address/auth redaction.
    sensitive = re.compile(
        r"(?i)\b(?:pin|pair(?:ing|ed)?|certificates?|credentials?|cookie|token|secret|password|bearer)\b"
    )
    return "\n".join(line for line in log.splitlines() if not sensitive.search(line))


def inspect():
    if not HISTORY.exists():
        print("TRIAL_EVIDENCE=NONE")
        return
    private_directory(HISTORY)
    candidates = sorted(
        path for path in HISTORY.iterdir() if re.fullmatch(r"\d{8}T\d{6}Z-[a-f0-9]{12}", path.name)
    )
    if not candidates:
        print("TRIAL_EVIDENCE=NONE")
        return
    snapshot = candidates[-1]
    private_directory(snapshot)
    inspector = module("trial_redacted_inspector", "inspect-session.py")
    metrics = module("trial_numeric_metrics", "trial-metrics.py")
    summary = {
        "snapshot": snapshot.name,
        "cleanup_completed": (snapshot / "finished.json").exists(),
        "errors": [],
        "log_prefix_bytes_omitted": {},
        "raw_log_printed": False,
    }
    for name in ("guardian.log", "session.log"):
        path = snapshot / name
        if not path.exists():
            continue
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(fd, "rb") as stream:
            info = os.fstat(stream.fileno())
            if (
                not stat.S_ISREG(info.st_mode)
                or info.st_uid != 0
                or stat.S_IMODE(info.st_mode) != 0o600
            ):
                raise ValueError("expected a private root-owned trial log")
            # Older workers appended Sunshine's log at shutdown; new workers
            # inherit this evidence FD and write it live. Keep early canvas
            # samples in either layout, with a fixed read ceiling.
            limit = 16 * 1024 * 1024
            offset = max(0, info.st_size - limit)
            stream.seek(offset)
            log = without_pairing_details(stream.read(limit).decode(errors="replace"))
            summary["log_prefix_bytes_omitted"][name] = offset
        summary["errors"].extend(
            inspector.redact(line)
            for line in log.splitlines()
            if line.startswith("FAIL|moonlight_trial|")
        )
        if name == "session.log":
            summary["session"] = inspector.summarize(log)
            summary["performance"] = metrics.summarize(log)
    summary["errors"] = summary["errors"][-12:]
    print(json.dumps(summary, indent=2))


def interrupted(_signum, _frame):
    raise InterruptedError("trial interrupted")


def main():
    global TOOLS, BUNDLE
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tools", type=Path, required=True)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument(
        "action",
        choices=("start", "status", "stop", "inspect", "guardian", "cleanup", "worker", "inner"),
    )
    parser.add_argument("--preset", choices=capture.PRESETS, default="4k60")
    args = parser.parse_args()
    if os.geteuid() != 0 and args.action != "inner":
        raise ValueError("use the operator script; root required for controller actions")
    TOOLS = json.loads(args.tools.read_text()) | {"manifest": str(args.tools)}
    BUNDLE = args.bundle.resolve(strict=True)
    if not re.fullmatch(r"/nix/store/[a-z0-9]{32}-[^/]+", str(BUNDLE)):
        raise ValueError("trial bundle must be an immutable Nix output")
    os.umask(0o077)
    for number in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(number, interrupted)
    if args.action == "start":
        start(args.preset)
    elif args.action in ("worker", "inner"):
        HOST.session(args.action)
    else:
        globals()[args.action]()


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"FAIL|moonlight_trial|{error}", file=sys.stderr)
        sys.exit(1)
