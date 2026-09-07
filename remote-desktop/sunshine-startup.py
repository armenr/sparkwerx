"""Sunshine display/encoder startup probe, not a frame-capture or streaming test.

Called only inside session-test.py's private, no-IP, no-input transient service.
Sunshine's pinned video::validate_config encodes dummy images during startup;
positive encoder messages cannot establish real changing-frame capture or FPS.
"""

import json
import re
import subprocess
import sys
import time
from pathlib import Path

CODECS = {"H.264": "h264_nvenc", "HEVC": "hevc_nvenc", "AV1": "av1_nvenc"}
MAX_LOG_BYTES = 1024 * 1024


def configuration(directory, output):
    if not re.fullmatch(r"[A-Z0-9-]+", output):
        raise ValueError("unexpected private virtual-output name")
    return {
        "capture": "wlr",
        "encoder": "nvenc",
        "output_name": output,
        "hevc_mode": "2",
        "av1_mode": "2",
        "dd_configuration_option": "disabled",
        "keyboard": "disabled",
        "mouse": "disabled",
        "controller": "disabled",
        "native_pen_touch": "disabled",
        "stream_audio": "disabled",
        "install_steam_audio_drivers": "disabled",
        "system_tray": "disabled",
        "upnp": "disabled",
        "notify_pre_releases": "disabled",
        "bind_address": "127.0.0.1",
        "origin_web_ui_allowed": "pc",
        "sunshine_name": "sparkwerx-startup-test",
        "file_apps": str(directory / "apps.json"),
        "file_state": str(directory / "state.json"),
        "credentials_file": str(directory / "credentials.json"),
        "pkey": str(directory / "key.pem"),
        "cert": str(directory / "cert.pem"),
        "log_path": "/dev/null",
        "min_log_level": "debug",
    }


def expected_report(preset, version, output):
    return {
        "kind": "sunshine-startup-only",
        "version": version,
        "output": output,
        "display": preset,
        "encoders": list(CODECS.values()),
        "changing_frame_capture_tested": False,
        "streaming_tested": False,
    }


def missing_evidence(log, preset, version):
    # Never treat exit status, "Trying encoder", or an advertised capability as
    # success. These are the pinned source's final successful-probe messages.
    if "Unrecognized configurable option" in log:
        raise RuntimeError("Sunshine rejected a diagnostic configuration option")
    if re.search(r"Found .+ encoder: .+ \[(?!nvenc\])", log):
        raise RuntimeError("Sunshine selected an unexpected encoder backend")
    evidence = {
        "Wayland backend": "Screencasting with Wayland's protocol",
        "selected display": "[wlgrab] Selected monitor [",
    }
    evidence.update(
        {name: f"Found {name} encoder: {codec} [nvenc]" for name, codec in CODECS.items()}
    )
    missing = [name for name, marker in evidence.items() if marker not in log]
    if not re.search(r"Sunshine version: " + re.escape(version) + r"(?:\s|$)", log):
        missing.append("package version")
    dimensions = re.findall(r"\[wlgrab\] Resolution: (\d+)x(\d+)\b", log)
    expected = (str(preset["width"]), str(preset["height"]))
    if not dimensions:
        missing.append("display dimensions")
    elif any(pair != expected for pair in dimensions):
        raise RuntimeError("Sunshine initialized an unexpected display size")
    return missing


def read_log(path):
    with path.open("rb") as stream:
        data = stream.read(MAX_LOG_BYTES + 1)
    if len(data) > MAX_LOG_BYTES:
        raise RuntimeError("Sunshine startup log exceeded the diagnostic size limit")
    return data.decode("utf-8", errors="replace")


def probe(tools, preset, output, env, stop, verify_isolation):
    # The caller checks normal-user identity/capabilities and a dedicated
    # compositor. Repeat the no-IP/no-input checks immediately before Sunshine.
    verify_isolation()
    directory = Path(env["HOME"]) / "sunshine-startup"
    directory.mkdir(mode=0o700)
    (directory / "apps.json").write_text(json.dumps({"env": {}, "apps": []}))
    config = directory / "sunshine.conf"
    config.write_text(
        "".join(f"{key} = {value}\n" for key, value in configuration(directory, output).items())
    )
    log_path = directory / "console.log"
    child = None
    log = ""
    try:
        with log_path.open("wb") as stream:
            child = subprocess.Popen(
                [tools["sunshine"], str(config)],
                env=env,
                cwd=directory,
                stdin=subprocess.DEVNULL,
                stdout=stream,
                stderr=subprocess.STDOUT,
            )
            deadline = time.monotonic() + 60
            while True:
                log = read_log(log_path)
                missing = missing_evidence(log, preset, tools["sunshineVersion"])
                if not missing:
                    break
                if child.poll() is not None:
                    raise RuntimeError("Sunshine startup lacks: " + ", ".join(missing))
                if time.monotonic() >= deadline:
                    raise TimeoutError("Sunshine startup timed out; missing: " + ", ".join(missing))
                time.sleep(0.1)
    finally:
        stop(child)
        # This output goes only to the enclosing root-private session log.
        # IP sockets remain denied even if Sunshine reaches listener startup
        # between the successful encoder messages and our stop signal.
        if log_path.exists():
            with log_path.open("rb") as stream:
                log = stream.read(MAX_LOG_BYTES).decode("utf-8", errors="replace")
            sys.stdout.write(log)
            sys.stdout.flush()
    # Reject an unexpected config/backend error that arrived just before stop.
    if missing_evidence(log, preset, tools["sunshineVersion"]):
        raise RuntimeError("Sunshine startup evidence was incomplete after shutdown")
    verify_isolation()
    return expected_report(preset, tools["sunshineVersion"], output)
