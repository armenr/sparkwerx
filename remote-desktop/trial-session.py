"""Private, temporary GPU session for the separate Moonlight trial."""

import importlib.util
import ipaddress
import json
import os
import pwd
import re
import socket
import stat
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
WORKER = "sparkwerx-moonlight-session.service"
RESULT = Path("/run/sparkwerx-result")


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


capture = module("trial_session_helpers", "session-test.py")
startup = module("trial_sunshine_helpers", "sunshine-startup.py")


def isolated():
    # Unlike the unchanged offline diagnostic, this service permits IP sockets.
    # The root guardian first installs the Tailscale-only ingress guard. Keep
    # all physical input, host D-Bus, homes, and unnecessary devices hidden.
    if not re.search(rf"/{re.escape(WORKER)}(?:/|$)", Path("/proc/self/cgroup").read_text()):
        raise RuntimeError("trial session is outside its private service")
    for path in (*capture.FORBIDDEN_DEVICES, "/run/systemd/private", "/run/dbus/system_bus_socket"):
        if os.path.lexists(path):
            raise RuntimeError("trial exposes an unexpected host device or IPC socket")
    capture.validate_cuda_device()
    if os.geteuid() != 0:
        if os.geteuid() != 1000 or not re.search(
            r"^CapEff:\s+0+$", Path("/proc/self/status").read_text(), re.MULTILINE
        ):
            raise RuntimeError("trial graphics must run as the unprivileged pilot user")
        capture.verify_user_device_access(sunshine=True)


def configuration(directory, context):
    address = ipaddress.ip_address(context["address"])
    if address.version != 4 or address not in ipaddress.ip_network("100.64.0.0/10"):
        raise ValueError("trial requires a verified Tailscale IPv4 address")
    return startup.configuration(directory, capture.display.OUTPUT) | {
        "address_family": "ipv4",
        "bind_address": str(address),
        "port": "47989",
        # SSH forwards to our own Tailscale address through loopback. The nft
        # rule denies admin access on every non-loopback interface, even tailscale0.
        "origin_web_ui_allowed": "wan",
        "lan_encryption_mode": "2",
        "wan_encryption_mode": "2",
        "sunshine_name": "Sparkwerx private trial",
        "keyboard": "enabled",
        "mouse": "enabled",
        "nvenc_preset": "1",
        "nvenc_twopass": "quarter_res",
    }


def small_json(path, uid):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd) as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != uid or info.st_size > 4096:
            raise ValueError("unexpected private session metadata")
        return json.load(stream)


def worker(tools, bundle):
    isolated()
    context = small_json(RESULT / "context.json", 0)
    account = pwd.getpwnam("n0b0dy")
    if account.pw_uid != 1000 or account.pw_gid != 1000:
        raise ValueError("trial requires the reviewed pilot user mapping")
    capture.RUNTIME.mkdir(mode=0o755)
    capture.RUNTIME.chmod(0o755)
    directory = capture.RUNTIME / "user"
    directory.mkdir(mode=0o700)
    os.chown(directory, account.pw_uid, account.pw_gid)
    child = broker = None
    try:
        broker = subprocess.Popen(
            [tools["seatd"], "-u", "n0b0dy", "-g", "n0b0dy", "-l", "info"],
            env={"PATH": "/usr/bin:/bin", "SEATD_VTBOUND": "0"},
            stdin=subprocess.DEVNULL,
        )
        deadline = time.monotonic() + 5
        while not Path("/run/seatd.sock").is_socket():
            if broker.poll() is not None or time.monotonic() >= deadline:
                raise RuntimeError("private seat broker did not become ready")
            time.sleep(0.05)
        child = subprocess.Popen(
            [
                sys.executable,
                str(HERE / "trial-control.py"),
                "--tools",
                tools["manifest"],
                "--bundle",
                str(bundle),
                "inner",
            ],
            user=account.pw_uid,
            group=account.pw_gid,
            extra_groups=capture.user_device_groups(sunshine=True),
            env={"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"},
            stdin=subprocess.PIPE,
            text=True,
        )
        # Runtime addresses stay out of process arguments, Git, and the store.
        child.stdin.write(json.dumps(context))
        child.stdin.close()
        ready = False
        while time.monotonic() < context["started"] + context["limit"] - 15:
            if child.poll() is not None or broker.poll() is not None:
                raise RuntimeError("private session or seat broker exited")
            report = directory / "ready.json"
            if not ready and report.exists():
                if small_json(report, account.pw_uid) != {"ready": True}:
                    raise ValueError("unexpected private startup report")
                (RESULT / "ready.json.new").write_text('{"ready":true}')
                (RESULT / "ready.json.new").replace(RESULT / "ready.json")
                ready = True
            if not ready and time.monotonic() > context["started"] + 100:
                raise TimeoutError("private session did not become ready")
            time.sleep(0.1)
    finally:
        (RESULT / "ready.json").unlink(missing_ok=True)
        capture.stop(child)
        capture.stop(broker)


def inner(tools):
    isolated()
    context = json.loads(sys.stdin.read(4097))
    directory = capture.RUNTIME / "user"
    capture.validate_ipc_path(directory / "r")
    env = capture.session_environment(directory, context["driver"], tools)
    for name in ("r", "config", "cache", "data", "state"):
        (directory / name).mkdir(mode=0o700)
    preset = capture.PRESETS[context["preset"]]
    config = directory / "hyprland.conf"
    config.write_text(capture.test_config(preset))
    compositor = canvas = sunshine = None
    log_path = directory / "sunshine/console.log"
    try:
        compositor = subprocess.Popen(
            [tools["Hyprland"], "--config", str(config)], env=env, stdin=subprocess.DEVNULL
        )

        def instances():
            return json.loads(capture.text([tools["hyprctl"], "-j", "instances"], env=env))

        deadline = time.monotonic() + 30
        instance = None
        while time.monotonic() < deadline:
            if compositor.poll() is not None:
                raise RuntimeError("private compositor exited during startup")
            try:
                matches = [item for item in instances() if item.get("pid") == compositor.pid]
                if len(matches) == 1:
                    instance = matches[0]
                    break
            except (subprocess.CalledProcessError, json.JSONDecodeError):
                pass
            time.sleep(0.1)
        if instance is None:
            raise TimeoutError("private compositor IPC did not appear")
        signature = instance["instance"]

        def control(signature, *args):
            argv = [tools["hyprctl"], "--instance", signature]
            if args[0] == "monitors":
                return json.loads(capture.text([*argv, "-j", *args], env=env))
            return capture.text([*argv, *args], env=env)

        capture.display.prepare_output(control, instances, signature, compositor.pid, preset)
        wayland_socket = instance.get("wl_socket", "")
        if not re.fullmatch(r"wayland-\d+", wayland_socket):
            raise ValueError("unexpected private Wayland socket")
        env["WAYLAND_DISPLAY"] = wayland_socket
        capture.check_renderer(
            (Path(env["XDG_RUNTIME_DIR"]) / "hypr" / signature / "hyprland.log").read_text()
        )
        canvas = subprocess.Popen([tools["canvas"]], env=env, stdin=subprocess.DEVNULL)
        server_dir = directory / "sunshine"
        server_dir.mkdir(mode=0o700)
        # No shell/terminal or host-home app. Pairing credentials and certificates
        # live only on the session's private /run tmpfs and disappear at shutdown.
        (server_dir / "apps.json").write_text(
            json.dumps({"env": {}, "apps": [{"name": "Private test screen"}]})
        )
        server_config = server_dir / "sunshine.conf"
        server_config.write_text(
            "".join(
                f"{key} = {value}\n" for key, value in configuration(server_dir, context).items()
            )
        )
        with log_path.open("wb") as log:
            sunshine = subprocess.Popen(
                [tools["sunshine"], str(server_config)],
                env=env,
                cwd=server_dir,
                stdin=subprocess.DEVNULL,
                stdout=log,
                stderr=subprocess.STDOUT,
            )
            ready = False
            next_display = 0.0
            deadline = time.monotonic() + 65
            while time.monotonic() < context["started"] + context["limit"] - 20:
                if any(child.poll() is not None for child in (compositor, canvas, sunshine)):
                    raise RuntimeError("a private trial application exited")
                if log_path.stat().st_size > 8 * 1024 * 1024:
                    raise RuntimeError("private Sunshine log reached its size limit")
                if not ready:
                    text = startup.read_log(log_path)
                    if (
                        not startup.missing_evidence(text, preset, tools["sunshineVersion"])
                        and "Sparkwerx session-local Wayland keyboard/pointer ready" in text
                    ):
                        # Successful encoder probes alone do not prove a server.
                        # Require all four TCP listeners on the selected local IP.
                        try:
                            for port in (47984, 47989, 47990, 48010):
                                with socket.create_connection(
                                    (context["address"], port), timeout=0.2
                                ):
                                    pass
                        except OSError:
                            pass
                        else:
                            (directory / "ready.json").write_text('{"ready":true}')
                            ready = True
                    if not ready and time.monotonic() > deadline:
                        raise TimeoutError("Sunshine display/encoder/listener startup timed out")
                if time.monotonic() >= next_display:
                    capture.display.assert_dedicated_instance(
                        instances(), signature, compositor.pid
                    )
                    if not capture.display.validate_monitors(
                        control(signature, "monitors", "all"), preset, ready=True
                    ):
                        raise RuntimeError("private output mode changed")
                    next_display = time.monotonic() + 5
                time.sleep(0.1)
    finally:
        capture.stop(sunshine)
        capture.stop(canvas)
        capture.stop(compositor)
        if log_path.exists():
            # Root-private evidence only; the front door never prints this log.
            with log_path.open("rb") as stream:
                sys.stdout.buffer.write(stream.read(8 * 1024 * 1024))
                sys.stdout.flush()


def run(action, tools, bundle):
    if action == "worker":
        worker(tools, bundle)
    else:
        inner(tools)
