"""Temporary, no-listener Hyprland capture diagnostic; not a desktop activation route."""

import argparse
import errno
import hashlib
import importlib.util
import json
import os
import platform
import pwd
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
ROOT_PROFILE = Path("/nix/var/nix/profiles/system-manager-profiles/system-manager")
PILOT = "/nix/store/djp7ap9gc7kq6c5hhbqzzslvmg4vq3m1-system-manager"
DEVICES = (
    "/dev/dri/card1",
    "/dev/dri/renderD128",
    "/dev/nvidia0",
    "/dev/nvidiactl",
    "/dev/nvidia-modeset",
)
FORBIDDEN_DEVICES = ("/dev/dri/card0", "/dev/input", "/dev/uinput", "/dev/tty0")
GUARDS = ("desktop-switch", "tailscale-migration", "fleet-bootstrap", "root-reboot-recovery")
PRESETS = {
    "1440p120": {"width": 2560, "height": 1440, "fps": 120},
    "4k60": {"width": 3840, "height": 2160, "fps": 60},
    "4k120": {"width": 3840, "height": 2160, "fps": 120},
}
# Keep this private-namespace path short: Hyprland appends its commit/time/random
# instance signature and a socket name inside Linux's 107-byte pathname limit.
RUNTIME = Path("/run/sw")
KMS_MODESET = Path("/sys/module/nvidia_drm/parameters/modeset")
RESULT = Path("/run/sparkwerx-result/result.json")
SERVICE_PREFIX = "dgx-capture-test-"


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


gpu = module("capture_gpu", "gpu-probe.py")
display = module("capture_display", "virtual-display.py")


def run(args, **kwargs):
    return subprocess.run(
        [str(arg) for arg in args],
        check=True,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        timeout=kwargs.pop("timeout", 10),
        **kwargs,
    )


def text(args, **kwargs):
    return run(args, **kwargs).stdout.decode().strip()


def kms_enabled():
    # Read the loaded module, not a config file that might have been overridden
    # or changed after boot. In particular, NVIDIA ships a modeset=0 package.
    value = KMS_MODESET.read_text(encoding="ascii").strip()
    if value not in ("Y", "N"):
        raise ValueError("unexpected NVIDIA DRM modeset value; no graphics started")
    return value == "Y"


def check_kms():
    # A deliberately read-only branch: no GPU open/ioctl, subprocess, service,
    # snapshot, config write, module reload, or inference from connector count.
    if os.geteuid() != 0 or platform.machine() != "aarch64" or socket.gethostname() != "sparkle-01":
        raise ValueError("this check requires sudo on the reviewed sparkle-01 pilot")
    enabled = kms_enabled()
    print("NVIDIA_DRM_MODESET=" + ("Y" if enabled else "N"))
    print("KMS_STATUS=" + ("ENABLED" if enabled else "DISABLED"))
    print("READ_ONLY: no graphics, driver setting, service, or boot change was performed.")
    if not enabled:
        print("HOLD: KMS must be enabled through a separately reviewed host change before capture.")


def validate_ipc_path(runtime_dir):
    # Match the pinned constructor's 40-char commit, time_t, and 31-bit random
    # suffix. Reserve 20 timestamp digits rather than depending on today's date.
    signature = "f" * 40 + "_" + "9" * 20 + "_" + "9" * 10
    for name in (".socket.sock", ".socket2.sock"):
        if len(os.fsencode(runtime_dir / "hypr" / signature / name)) > 107:
            raise ValueError("private runtime path is too long for Hyprland IPC")


def unit_properties(result_dir):
    # /run (including seatd's compile-time /run/seatd.sock) is private. Bind
    # only device metadata and a root-only result directory into that namespace.
    return {
        "Type": "exec",
        "RuntimeMaxSec": "150s",
        "TimeoutStopSec": "5s",
        "KillMode": "control-group",
        "SendSIGKILL": "yes",
        "Restart": "no",
        "UMask": "0077",
        "Environment": "PATH=/usr/bin:/bin LANG=C.UTF-8",
        "UnsetEnvironment": "LD_PRELOAD LD_LIBRARY_PATH LD_AUDIT PYTHONPATH PYTHONHOME",
        "PrivateNetwork": "yes",
        "RestrictAddressFamilies": "AF_UNIX AF_NETLINK",
        "PrivateDevices": "yes",
        "DevicePolicy": "closed",
        "BindPaths": " ".join((*DEVICES, f"{result_dir}:/run/sparkwerx-result")),
        "BindReadOnlyPaths": "-/run/udev/data:/run/udev/data",
        "TemporaryFileSystem": "/run:rw,nosuid,nodev,size=128M",
        "ProtectSystem": "strict",
        "ProtectHome": "yes",
        "PrivateTmp": "yes",
        "NoNewPrivileges": "yes",
        "ProtectKernelTunables": "yes",
        "ProtectKernelModules": "yes",
        "ProtectControlGroups": "yes",
        "RestrictNamespaces": "yes",
        "RestrictRealtime": "yes",
        "LockPersonality": "yes",
        "LimitCORE": "0",
        "MemoryMax": "2G",
        "TasksMax": "128",
        # The broker may need DRM-master ioctls. The compositor gets NO root
        # capabilities: setuid + exec drops them before it starts. No CAP_MKNOD,
        # SYS_MODULE, SYS_TTY_CONFIG, NET_ADMIN, or host IPC socket is supplied.
        "CapabilityBoundingSet": (
            "CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_SETGID CAP_SETUID CAP_KILL CAP_SYS_ADMIN"
        ),
    }


def verify_isolation():
    for family in (socket.AF_INET, socket.AF_INET6):
        for kind in (socket.SOCK_STREAM, socket.SOCK_DGRAM):
            try:
                connection = socket.socket(family, kind)
            except OSError as error:
                if error.errno not in (errno.EAFNOSUPPORT, errno.EPERM, errno.EACCES):
                    raise
            else:
                connection.close()
                raise RuntimeError("network socket creation was not denied")
    for path in (*FORBIDDEN_DEVICES, "/run/systemd/private", "/run/dbus/system_bus_socket"):
        if os.path.lexists(path):
            raise RuntimeError(f"unexpected host device or IPC exposure: {path}")
    left, right = socket.socketpair()
    left.close()
    right.close()


def test_config(preset):
    return (
        display.render_config(preset)
        + """
animations {
    enabled = false
}
ecosystem {
    no_update_news = true
    no_donation_nag = true
}
debug {
    disable_logs = false
    enable_stdout_logs = true
    colored_stdout_logs = false
}
"""
    )


def session_environment(directory, version, tools):
    bridge = directory / "driver"
    # Reuse the already-tested NVIDIA-only GLVND bridge without changing its
    # old derivation. The two additions are the factory GBM allocator/platform.
    env = gpu.driver_bridge(bridge, version, graphics=True)
    allocator = gpu.trusted_driver_file(
        Path("/usr/lib/aarch64-linux-gnu/libnvidia-allocator.so.1"),
        "libnvidia-allocator",
        version,
    )
    platform_file = Path("/usr/lib/aarch64-linux-gnu/libnvidia-egl-gbm.so.1").resolve(strict=True)
    match = re.fullmatch(r"libnvidia-egl-gbm\.so\.(\d+\.\d+\.\d+)", platform_file.name)
    if not match:
        raise ValueError("unexpected factory EGL GBM platform version")
    platform_file = gpu.trusted_driver_file(platform_file, "libnvidia-egl-gbm", match[1])
    (bridge / "nvidia-drm_gbm.so").symlink_to(allocator)
    (bridge / "libnvidia-allocator.so.1").symlink_to(allocator)
    # Resolve only the platform's two non-driver dependencies through the
    # locked Nix libraries, never a blanket /usr/lib search path.
    for name in ("libgbm.so.1", "libdrm.so.2"):
        (bridge / name).symlink_to(tools[name])
    platform_json = bridge / "gbm.json"
    platform_json.write_text(
        json.dumps(
            {
                "file_format_version": "1.0.0",
                "ICD": {
                    "library_path": str(platform_file),
                },
            }
        )
    )
    # Do not carry the caller's LD_*, display, D-Bus, or session variables in.
    env = {
        key: value
        for key, value in env.items()
        if key
        in (
            "LD_LIBRARY_PATH",
            "__EGL_VENDOR_LIBRARY_FILENAMES",
            "__GL_SHADER_DISK_CACHE",
            "CUDA_CACHE_DISABLE",
        )
    }
    env.update(
        {
            "PATH": "/usr/bin:/bin",
            "LANG": "C.UTF-8",
            "HOME": str(directory),
            "XDG_RUNTIME_DIR": str(directory / "r"),
            "XDG_CONFIG_HOME": str(directory / "config"),
            "XDG_CACHE_HOME": str(directory / "cache"),
            "XDG_DATA_HOME": str(directory / "data"),
            "XDG_STATE_HOME": str(directory / "state"),
            "LIBSEAT_BACKEND": "seatd",
            "SEATD_SOCK": "/run/seatd.sock",
            "AQ_DRM_DEVICES": "/dev/dri/card1",
            "GBM_BACKEND": "nvidia-drm",
            "GBM_BACKENDS_PATH": str(bridge),
            "__EGL_EXTERNAL_PLATFORM_CONFIG_FILENAMES": str(platform_json),
            "HYPRLAND_NO_SD_VARS": "1",
            "HYPRLAND_NO_SD_NOTIFY": "1",
            "HYPRLAND_NO_RT": "1",
            "HYPRLAND_NO_CRASHREPORTER": "1",
        }
    )
    return env


def check_ppm(data, preset, color):
    # Grim's P6 output is simple RGB8. Accept header whitespace, but
    # never skip arbitrary whitespace in the pixel payload (it may be a pixel).
    header = re.match(rb"P6\s+(\d+)\s+(\d+)\s+255\r?\n", data)
    if not header:
        raise ValueError("capture is not the expected RGB8 PPM")
    width, height = int(header[1]), int(header[2])
    if (width, height) != (preset["width"], preset["height"]):
        raise ValueError("captured dimensions do not match the requested mode")
    pixels = memoryview(data)[header.end() :]
    if len(pixels) != width * height * 3:
        raise ValueError("capture payload length is wrong")
    expected = {"red": (255, 0, 0), "green": (0, 255, 0)}[color]
    for y in (height // 4, height // 2, 3 * height // 4):
        for x in (width // 4, width // 2, 3 * width // 4):
            pixel = pixels[(y * width + x) * 3 : (y * width + x) * 3 + 3]
            if any(
                abs(actual - target) > 15 for actual, target in zip(pixel, expected, strict=True)
            ):
                raise ValueError(f"capture did not contain the expected {color} frame")
    return hashlib.sha256(data).hexdigest()


def check_renderer(log):
    if not re.search(r"Vendor:\s+NVIDIA Corporation", log) or not re.search(
        r"Renderer:[^\n]*\bGB10\b", log
    ):
        raise ValueError("the compositor log does not identify the NVIDIA GB10 renderer")


def stop(child):
    if child is None or child.poll() is not None:
        return
    child.terminate()
    try:
        child.wait(timeout=3)
    except subprocess.TimeoutExpired:
        child.kill()
        child.wait(timeout=2)


def capture_session(tools, preset_name, version):
    if os.geteuid() == 0:
        raise RuntimeError("Hyprland must never run as root")
    verify_isolation()
    status = Path("/proc/self/status").read_text()
    if not re.search(r"^CapEff:\s+0+$", status, re.MULTILINE):
        raise RuntimeError("compositor user still has effective capabilities")
    directory = RUNTIME / "user"
    validate_ipc_path(directory / "r")
    env = session_environment(directory, version, tools)
    for name in ("r", "config", "cache", "data", "state"):
        (directory / name).mkdir(mode=0o700)
    preset = PRESETS[preset_name]
    config = directory / "hyprland.conf"
    config.write_text(test_config(preset))
    child = None
    client = None
    try:
        child = subprocess.Popen(
            [tools["Hyprland"], "--config", str(config)], env=env, stdin=subprocess.DEVNULL
        )

        def instances():
            return json.loads(text([tools["hyprctl"], "-j", "instances"], env=env))

        deadline = time.monotonic() + 30
        instance = None
        while time.monotonic() < deadline:
            if child.poll() is not None:
                raise RuntimeError(f"Hyprland exited during startup: {child.returncode}")
            try:
                matches = [item for item in instances() if item.get("pid") == child.pid]
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
            command = [tools["hyprctl"], "--instance", signature]
            if args[0] == "monitors":
                return json.loads(text([*command, "-j", *args], env=env))
            return text([*command, *args], env=env)

        display.prepare_output(control, instances, signature, child.pid, preset)
        wayland_socket = instance.get("wl_socket", "")
        if not re.fullmatch(r"wayland-\d+", wayland_socket):
            raise ValueError("private compositor reported an unexpected Wayland socket")
        env["WAYLAND_DISPLAY"] = wayland_socket
        frames = {}
        for color in ("red", "green"):
            display.assert_dedicated_instance(instances(), signature, child.pid)
            if not display.validate_monitors(
                control(signature, "monitors", "all"), preset, ready=True
            ):
                raise RuntimeError("private output mode changed before capture")
            client = subprocess.Popen([tools["client"], color], env=env, stdin=subprocess.DEVNULL)
            deadline = time.monotonic() + 8
            while True:
                if client.poll() is not None:
                    raise RuntimeError("test-color client exited before capture")
                frame = run([tools["grim"], "-o", display.OUTPUT, "-t", "ppm", "-"], env=env).stdout
                try:
                    frames[color] = check_ppm(frame, preset, color)
                    break
                except ValueError:
                    if time.monotonic() >= deadline:
                        raise
                    time.sleep(0.1)
            stop(client)
            client = None
        check_renderer(
            (Path(env["XDG_RUNTIME_DIR"]) / "hypr" / signature / "hyprland.log").read_text()
        )
        # Only generated pixels were read; do not persist screenshots.
        (directory / "frames.json").write_text(json.dumps(frames))
    except subprocess.CalledProcessError as error:
        # This process only writes into the private diagnostic log, never the
        # operator's terminal. Preserve compositor/capture command diagnostics.
        sys.stderr.buffer.write(error.stderr or b"")
        raise
    finally:
        stop(client)
        stop(child)


def worker(tools, user, preset, version):
    if os.geteuid() != 0 or not re.search(
        rf"/{SERVICE_PREFIX}[a-f0-9]{{12}}\.service(?:/|$)",
        Path("/proc/self/cgroup").read_text().strip(),
    ):
        raise RuntimeError("worker must run inside its unique transient service")
    verify_isolation()
    account = pwd.getpwnam(user)
    if account.pw_uid != 1000 or user != "n0b0dy":
        raise ValueError("this pilot test requires the reviewed n0b0dy account")
    RUNTIME.mkdir(mode=0o755)
    RUNTIME.chmod(0o755)
    directory = RUNTIME / "user"
    directory.mkdir(mode=0o700)
    os.chown(directory, account.pw_uid, account.pw_gid)
    broker = None
    child = None
    report = {"passed": False}
    try:
        # seatd 0.9.3 uses a compile-time socket path, NOT SEATD_SOCK.
        # The namespace hides /run/seatd.sock; only libseat uses SEATD_SOCK.
        broker = subprocess.Popen(
            [tools["seatd"], "-u", user, "-g", user, "-l", "info"],
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
                __file__,
                "inner",
                "--tools",
                str(tools["manifest"]),
                "--preset",
                preset,
                "--driver",
                version,
            ],
            user=account.pw_uid,
            group=account.pw_gid,
            extra_groups=[Path("/dev/dri/renderD128").stat().st_gid],
            env={"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"},
            stdin=subprocess.DEVNULL,
        )
        if child.wait(timeout=115) != 0:
            raise RuntimeError("private compositor/capture test failed; see the private log")
        # The normal user's summary is only data, not an executable/root action.
        descriptor = os.open(directory / "frames.json", os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(descriptor, "r") as stream:
            info = os.fstat(stream.fileno())
            if (
                not stat.S_ISREG(info.st_mode)
                or info.st_uid != account.pw_uid
                or info.st_size > 1024
            ):
                raise ValueError("capture summary is not a small regular user-owned file")
            frames = json.load(stream)
        if (
            set(frames) != {"red", "green"}
            or any(
                not isinstance(value, str) or not re.fullmatch(r"[a-f0-9]{64}", value)
                for value in frames.values()
            )
            or frames["red"] == frames["green"]
        ):
            raise RuntimeError("invalid capture result")
        report = {"passed": True, "preset": preset, "frames": frames}
    finally:
        stop(child)
        stop(broker)
        RESULT.write_text(json.dumps(report))


def device_snapshot():
    result = {}
    for name in (*DEVICES, *FORBIDDEN_DEVICES):
        path = Path(name)
        if not path.exists():
            result[name] = None
            continue
        info = path.stat()
        result[name] = [
            info.st_uid,
            info.st_gid,
            info.st_mode,
            info.st_rdev,
            {key: os.getxattr(path, key).hex() for key in os.listxattr(path)},
        ]
    return result


def host_snapshot():
    result = {
        "units_profile": gpu.host_snapshot(),
        "devices": device_snapshot(),
        "boot": Path("/proc/sys/kernel/random/boot_id").read_text(),
    }
    result["files"] = {
        name: hashlib.sha256(Path(name).read_bytes()).hexdigest()
        for name in (
            "/etc/passwd",
            "/etc/group",
            "/etc/nix/nix.conf",
            "/var/lib/system-manager/state/system-manager-state.json",
        )
    }
    result["gpu"] = text(
        ["/usr/bin/nvidia-smi", "--query-gpu=name,driver_version", "--format=csv,noheader"]
    )
    ts = json.loads(text(["/usr/bin/tailscale", "status", "--json"]))
    prefs = json.loads(text(["/usr/bin/tailscale", "debug", "prefs"]))
    if (
        ts.get("BackendState") != "Running"
        or ts.get("Self", {}).get("Online") is not True
        or prefs.get("WantRunning") is not True
        or prefs.get("RunSSH") is not True
    ):
        raise RuntimeError("Tailscale access is not healthy")
    result["tailscale_identity"] = hashlib.sha256(str(ts["Self"]["ID"]).encode()).hexdigest()
    if text(["/usr/bin/systemctl", "is-system-running"]) != "running":
        raise RuntimeError("systemd is not healthy")
    return result


def preflight():
    if os.geteuid() != 0 or platform.machine() != "aarch64" or socket.gethostname() != "sparkle-01":
        raise ValueError("this hardware test requires sudo on the reviewed sparkle-01 pilot")
    if str(ROOT_PROFILE.resolve(strict=True)) != PILOT:
        raise ValueError("live root profile is not the reviewed headless generation five")
    if not kms_enabled():
        raise ValueError(
            "NVIDIA DRM KMS is disabled (modeset=N); no graphics started. "
            "Enabling it needs a separately reviewed host change, not a permission workaround."
        )
    before = host_snapshot()
    if "NeedDaemonReload=yes" in before["units_profile"][0]:
        raise ValueError("a protected unit has a pending daemon reload")
    for name in ("gdm.service", "dgx-dashboard.service"):
        if text(["systemctl", "show", name, "-p", "ActiveState", "--value"]) != "inactive":
            raise ValueError("factory graphics must already be inactive")
    for name in (
        "dgx-headless.target",
        "docker.service",
        "dgx-dashboard-admin.service",
        "nvidia-persistenced.service",
        "tailscaled.service",
    ):
        if text(["systemctl", "show", name, "-p", "ActiveState", "--value"]) != "active":
            raise ValueError(f"required unit is not already active: {name}")
    for guard in GUARDS:
        if os.path.lexists(f"/var/lib/dgx-setup/{guard}"):
            raise ValueError("a deployment/recovery guard exists; inspect it before testing")
    units = json.loads(text(["systemctl", "list-units", "--all", "--output=json", "--no-pager"]))
    for unit in units:
        name = unit["unit"]
        if (
            name.startswith("dgx-")
            and ("rollback" in name or "recovery" in name or name.startswith(SERVICE_PREFIX))
            and unit["active"]
            in (
                "active",
                "activating",
                "deactivating",
            )
        ):
            raise ValueError("an active diagnostic or recovery unit exists")
    for comm in Path("/proc").glob("[0-9]*/comm"):
        try:
            if comm.read_text().strip() in (
                "Hyprland",
                "gnome-shell",
                "Xorg",
                "sway",
                "weston",
                "sunshine",
            ):
                raise ValueError("an existing compositor or capture server is running")
        except (FileNotFoundError, ProcessLookupError):
            pass
    for name in DEVICES:
        if not stat.S_ISCHR(Path(name).stat().st_mode):
            raise ValueError("a required GPU device is missing")
    for node in ("card1", "renderD128"):
        if Path(f"/sys/class/drm/{node}/device/driver").resolve().name != "nvidia":
            raise ValueError("the reviewed DRM device is not driven by NVIDIA")
    if (
        Path("/sys/class/drm/card1/device").resolve()
        != Path("/sys/class/drm/renderD128/device").resolve()
    ):
        raise ValueError("DRM card and render node do not belong to the same GPU")
    return before


def host(tools, repo, preset):
    before = preflight()
    if repo != Path("/home/n0b0dy/Development/DGX-setup") or repo.is_symlink():
        raise ValueError("use the reviewed pilot checkout for private diagnostic evidence")
    # An abstract Unix lock is released automatically, including on process
    # death. A second launch is also refused while the transient unit is alive.
    with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as lock:
        lock.bind("\0sparkwerx-private-capture-test")
        unit = SERVICE_PREFIX + uuid.uuid4().hex[:12] + ".service"
        base = repo / "inventory/sparkle-01/raw/remote-desktop-session"
        for parent in (base, *base.parents):
            if parent.is_symlink():
                raise ValueError("private evidence path has a symlink ancestor")
        base.mkdir(mode=0o700, exist_ok=True)
        if base.stat().st_uid != 0 or stat.S_IMODE(base.stat().st_mode) != 0o700:
            raise ValueError("diagnostic evidence directory must be root-owned mode 0700")
        snapshot = base / (time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()) + "-" + unit[17:29])
        snapshot.mkdir(mode=0o700)
        results = snapshot / "result"
        results.mkdir(mode=0o700)
        log = snapshot / "session.log"
        log.touch(mode=0o600)
        (snapshot / "before.json").write_text(json.dumps(before, indent=2))
        version = text(
            ["/usr/bin/nvidia-smi", "--query-gpu=driver_version", "--format=csv,noheader"]
        )
        if not re.fullmatch(r"\d+\.\d+\.\d+", version):
            raise ValueError("expected one factory NVIDIA driver")
        properties = unit_properties(results)
        (snapshot / "unit.json").write_text(json.dumps(properties, indent=2))
        (snapshot / "context.json").write_text(
            json.dumps(
                {
                    "unit": unit,
                    "program": __file__,
                    "python": sys.executable,
                    "tools": tools,
                    "preset": preset,
                    "driver": version,
                },
                indent=2,
            )
        )
        command = [
            "/usr/bin/systemd-run",
            "--quiet",
            "--wait",
            "--collect",
            "--pipe",
            f"--unit={unit}",
        ]
        command += [f"--property={key}={value}" for key, value in properties.items()]
        command += [f"--property=DeviceAllow={device} rw" for device in DEVICES]
        command += [
            sys.executable,
            __file__,
            "worker",
            "--tools",
            tools["manifest"],
            "--user",
            "n0b0dy",
            "--driver",
            version,
            "--preset",
            preset,
        ]
        print(f"INFO|private_log|{log}", flush=True)
        print(
            "INFO|temporary_session|150-second hard limit; no input or TCP/UDP; no desktop switch",
            flush=True,
        )
        completed = False
        try:
            # Recheck immediately before privilege is made available to the
            # transient unit, after preparing evidence but before GPU mutation.
            if preflight() != before:
                raise RuntimeError("host changed during diagnostic preparation")
            # --pipe passes these already-open private file descriptors to the
            # service. It never needs access to the hidden /home path, and its
            # output is independent of the SSH terminal's lifetime.
            with log.open("ab", buffering=0) as stream:
                try:
                    subprocess.run(
                        command,
                        stdin=subprocess.DEVNULL,
                        stdout=stream,
                        stderr=stream,
                        timeout=170,
                        check=True,
                    )
                except subprocess.SubprocessError as error:
                    raise RuntimeError(f"transient GPU test failed; inspect {log}") from error
            report = json.loads((results / "result.json").read_text())
            if report.get("passed") is not True:
                raise RuntimeError("capture did not pass")
            completed = True
        finally:
            # --wait returns only after the unit is down. On interruption also
            # stop this exact unique unit; RuntimeMaxSec covers lost SSH/SIGKILL.
            state = text(["systemctl", "show", unit, "-p", "ActiveState", "--value"])
            if state not in ("inactive", "failed"):
                run(["systemctl", "stop", unit], timeout=15)
            try:
                journal = run(["/usr/bin/journalctl", "--no-pager", "-b", "-u", unit], timeout=10)
                (snapshot / "unit.journal").write_bytes(journal.stdout)
            except subprocess.SubprocessError:
                print(
                    "WARN|journal|could not collect the unit journal; checking host state anyway",
                    flush=True,
                )
            after = host_snapshot()
            (snapshot / "after.json").write_text(json.dumps(after, indent=2))
            if after != before:
                raise RuntimeError("host postflight differs; inspect private before/after evidence")
            print(
                "PASS|host_postflight|root profile, protected processes, access, files, and device permissions unchanged",
                flush=True,
            )
        if completed:
            print(
                f"PASS|temporary_capture|{preset}; red/green pixels verified; compositor and broker stopped"
            )
            print(
                "NOT_STREAMING: Sunshine capture, Moonlight latency, input/audio, and sustained FPS remain untested."
            )


def interrupted(signum, _frame):
    raise InterruptedError(f"interrupted by signal {signum}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("host", "worker", "inner"))
    parser.add_argument("--tools", required=True, type=Path)
    parser.add_argument("--repo", type=Path)
    parser.add_argument("--preset", choices=PRESETS, default="4k120")
    parser.add_argument("--driver")
    parser.add_argument("--user")
    parser.add_argument("--check-kms", action="store_true")
    args = parser.parse_args()
    if args.check_kms:
        if args.action != "host":
            parser.error("--check-kms is a host-only read-only check")
        check_kms()
        return
    os.umask(0o077)
    for number in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        signal.signal(number, interrupted)
    tools = json.loads(args.tools.read_text()) | {"manifest": str(args.tools)}
    if args.action == "host":
        host(tools, args.repo, args.preset)
    elif args.action == "worker":
        worker(tools, args.user, args.preset, args.driver)
    else:
        capture_session(tools, args.preset, args.driver)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"FAIL|temporary_capture|{error}", file=sys.stderr)
        sys.exit(1)
