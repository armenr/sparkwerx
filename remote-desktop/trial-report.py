"""Read-only reconnect report for saved Moonlight trials; never launch graphics."""

import argparse
import contextlib
import datetime
import importlib.util
import json
import os
import re
import stat
import statistics
from pathlib import Path

HERE = Path(__file__).resolve().parent
HISTORY = Path("/home/n0b0dy/Development/DGX-setup/inventory/sparkle-01/raw/moonlight-trial")
STAMP = re.compile(r"\d{8}T\d{6}Z-[a-f0-9]{12}")
RECORD = re.compile(
    r"^\[(\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?)\]: "
    r"(Debug|Info|Warning|Error|Fatal): (.*)$"
)
SENSITIVE = re.compile(
    r"(?i)\b(?:pin|pair(?:ing|ed)?|certificates?|credentials?|cookie|token|secret|password|bearer|auth\w*)\b"
)
EVENTS = {
    "CLIENT CONNECTED": "client_connected",
    "CLIENT DISCONNECTED": "client_disconnected",
    "Start capturing Video": "video_capture_started",
    "Start capturing Audio": "audio_capture_started",
    "Waiting for video to end...": "waiting_for_video_end",
    "Waiting for audio to end...": "waiting_for_audio_end",
    "Waiting for control to end...": "waiting_for_control_end",
    "Resetting Input...": "resetting_input",
    "Session ended": "session_ended",
    "Starting async encoder teardown": "encoder_teardown_started",
    "Async encoder teardown complete": "encoder_teardown_finished",
}


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


inspector = module("moonlight_report_redaction", "inspect-session.py")
metrics = module("moonlight_report_metrics", "trial-metrics.py")


def excerpt(values, limit):
    half = limit // 2
    return {
        "count": len(values),
        "items": values if len(values) <= limit else values[:half] + values[-half:],
        "omitted": max(0, len(values) - limit),
    }


def safe_message(text):
    # Drop whole authentication/pairing lines before the shared redactor.
    # Never echo control characters, input packets, or arbitrary debug messages.
    if SENSITIVE.search(text):
        return None
    return inspector.redact(re.sub(r"[\x00-\x1f\x7f]", "", text))


def summarize(session_log, guardian_log=""):
    events, canvas, wrappers = [], [], []
    groups = {}
    origin = None
    invalid_timestamps = oversized = sensitive = 0
    for original in session_log.splitlines():
        if len(original) > 8192:
            oversized += 1
            continue
        line = inspector.ANSI.sub("", original)
        if line.startswith("SPARKWERX_CANVAS_METRICS "):
            sample = metrics.canvas_sample(line.removeprefix("SPARKWERX_CANVAS_METRICS "))
            if sample is not None:
                canvas.append(sample)
            continue
        match = RECORD.fullmatch(line)
        if not match:
            continue
        try:
            timestamp = datetime.datetime.fromisoformat(match[1])
        except ValueError:
            invalid_timestamps += 1
            continue
        if origin is None:
            origin = timestamp
        elapsed = round((timestamp - origin).total_seconds(), 3)
        level, message = match[2], match[3]
        if SENSITIVE.search(message):
            sensitive += 1
            continue
        event = {"log_elapsed_s": elapsed}
        if message in EVENTS:
            events.append(event | {"event": EVENTS[message]})
        encoder = re.fullmatch(r"Creating encoder \[(h264_nvenc|hevc_nvenc|av1_nvenc)\]", message)
        if encoder:
            events.append(event | {"event": "encoder_created", "encoder": encoder[1]})
        bitrate = re.fullmatch(r"Streaming bitrate is (\d{1,9})", message)
        if bitrate:
            # Pinned video.cpp logs config.bitrate * 1000, in bits/second.
            events.append(event | {"event": "stream_bitrate", "bps": int(bitrate[1])})
        # Reuse strict numeric validation, never return a debug payload as text.
        numeric = metrics.summarize(line)
        for field, kind in (
            ("capture_requested_fps", "capture_rate_requested"),
            ("host_processing_ms", "host_processing_ms"),
            ("host_send_path_ms", "host_send_path_ms"),
        ):
            for value in numeric[field]["samples"]:
                events.append(event | {"event": kind, "value": value})
        if level in ("Warning", "Error", "Fatal"):
            redacted = safe_message(message)
            key = (level, redacted)
            if key not in groups:
                groups[key] = {
                    "level": level,
                    "message": redacted,
                    "count": 0,
                    "first_log_elapsed_s": elapsed,
                }
            groups[key]["count"] += 1
            groups[key]["last_log_elapsed_s"] = elapsed
    for source, log in (("session", session_log), ("guardian", guardian_log)):
        for line in log.splitlines():
            if line.startswith("FAIL|moonlight_trial|") and len(line) <= 8192:
                message = safe_message(line)
                if message is not None:
                    wrappers.append({"source": source, "message": message})
    errors = [value for (level, _), value in groups.items() if level in ("Error", "Fatal")]
    warnings = [value for (level, _), value in groups.items() if level == "Warning"]
    return {
        "timeline": excerpt(events, 128),
        "errors": excerpt(errors, 64),
        "warnings": excerpt(warnings, 24),
        "supervisor_messages": excerpt(wrappers, 12),
        "canvas": {
            "valid_windows": len(canvas),
            "last_elapsed_s": canvas[-1]["elapsed_s"] if canvas else None,
            "submit_fps_min_median_max": (
                [
                    min(sample["submit_fps"] for sample in canvas),
                    statistics.median(sample["submit_fps"] for sample in canvas),
                    max(sample["submit_fps"] for sample in canvas),
                ]
                if canvas
                else None
            ),
        },
        "invalid_timestamps": invalid_timestamps,
        "oversized_lines_omitted": oversized,
        "sensitive_records_omitted": sensitive,
        "notes": [
            "Timeline seconds are relative to the first valid Sunshine log timestamp, not canvas start.",
            "Log-clock changes can move timeline seconds backwards; input order is preserved.",
            "Encoder creation/capture requests include startup probes, not successful streamed frames.",
            "Host processing includes capture/processing/queues; send-path timing is not network RTT.",
            "Canvas submission rates are not GPU presentation or Moonlight received FPS.",
            "Supervisor exit messages alone do not distinguish a deadline from an earlier stream failure.",
        ],
        "raw_log_printed": False,
    }


@contextlib.contextmanager
def private_directory(path):
    if any(parent.is_symlink() for parent in (path, *path.parents)):
        raise ValueError("refusing a symlinked private evidence path")
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        info = os.fstat(fd)
        if info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o700:
            raise ValueError("expected root-owned mode-0700 evidence directory")
        yield fd
    finally:
        os.close(fd)


def private_file(directory_fd, name, limit):
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory_fd)
    except FileNotFoundError:
        return None, 0
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != 0
            or stat.S_IMODE(info.st_mode) != 0o600
        ):
            raise ValueError("expected root-owned mode-0600 regular evidence file")
        offset = max(0, info.st_size - limit)
        stream.seek(offset)
        return stream.read(limit).decode("utf-8", errors="replace"), offset


def read_report(stamp=None):
    if stamp is not None and not STAMP.fullmatch(stamp):
        raise ValueError("expected a trial snapshot name, not a path")
    with private_directory(HISTORY) as history_fd:
        if stamp is None:
            candidates = sorted(name for name in os.listdir(history_fd) if STAMP.fullmatch(name))
            if not candidates:
                raise ValueError("no saved Moonlight trial found")
            stamp = candidates[-1]
        with private_directory(HISTORY / stamp) as snapshot_fd:
            logs, offsets = {}, {}
            for name in ("session.log", "guardian.log"):
                text, offsets[name] = private_file(snapshot_fd, name, 16 * 1024 * 1024)
                logs[name] = text or ""
            finished, offset = private_file(snapshot_fd, "finished.json", 4096)
            cleanup = None
            if finished is not None:
                if offset:
                    raise ValueError("unexpected oversized cleanup record")
                value = json.loads(finished)
                fields = ("host_unchanged", "listeners_stopped", "network_guard_removed")
                if not isinstance(value, dict) or any(
                    type(value.get(key)) is not bool for key in fields
                ):
                    raise ValueError("unexpected cleanup record")
                cleanup = {key: value[key] for key in fields}
    return {
        "snapshot": stamp,
        "recorded_cleanup": cleanup,
        "log_prefix_bytes_omitted": offsets,
        **summarize(logs["session.log"], logs["guardian.log"]),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("snapshot", nargs="?")
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error("sudo is needed only to read saved private trial evidence")
    try:
        report = read_report(args.snapshot)
    except (OSError, ValueError):
        # Even error paths must not echo private paths or invalid file contents.
        parser.exit(
            1, "FAIL|trial_report|cannot read verified private evidence; no changes performed\n"
        )
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
