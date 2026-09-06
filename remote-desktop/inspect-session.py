"""Read a named private capture log and emit only a redacted error summary."""

import argparse
import json
import os
import re
import stat
from pathlib import Path

BASE = Path("/home/n0b0dy/Development/DGX-setup/inventory/sparkle-01/raw/remote-desktop-session")
STAMP = re.compile(r"\d{8}T\d{6}Z-[a-f0-9]{12}")


def redact(message):
    # This is an error excerpt, never a raw journal/inventory dump. Omit a
    # whole line if it might describe authentication, not just its value.
    if re.search(r"(?i)password|token|secret|credential|cookie|bearer|auth", message):
        return "<sensitive error detail withheld>"
    message = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", message)
    for pattern, replacement in (
        (r"https?://[^\s'\"]+", "<url>"),
        (r"[\w.+-]+@[\w.-]+", "<email>"),
        (r"\b[\w.-]+\.ts\.net\b", "<tailnet-name>"),
        (r"\b(?:\d{1,3}\.){3}\d{1,3}\b", "<ip>"),
        (r"(?<![\w])(?:[a-fA-F0-9]{0,4}:){2,}[a-fA-F0-9:.%]+", "<address>"),
        (r"/home/[^\s'\"]+", "<private-path>"),
        (r"/nix/store/[^/\s'\"]+", "<nix-store>"),
        (r"\b[A-Za-z0-9_-]{32,}\b", "<identifier>"),
    ):
        message = re.sub(pattern, replacement, message)
    return message[:500]


def summarize(log):
    errors = []
    frames = []
    for line in log.splitlines():
        frame = re.match(r'\s+File "[^"]*/([^/" ]+\.py)", line (\d+), in (\w+)', line)
        if frame:
            frames.append({"file": frame[1], "line": int(frame[2]), "function": frame[3]})
        elif re.match(r"^(?:FAIL\|temporary_capture\||[\w.]*(?:Error|Exception):)", line):
            errors.append(redact(line))
    return {
        "seat_broker_started": "seatd started" in log,
        "compositor_vendor_seen": "Vendor: NVIDIA Corporation" in log,
        "traceback": frames[-12:],
        "errors": errors[-12:],
        "raw_log_printed": False,
    }


def read_summary(stamp):
    if not STAMP.fullmatch(stamp):
        raise ValueError("expected a capture snapshot name, not a path")
    snapshot = BASE / stamp
    for path in (snapshot, *snapshot.parents):
        if path.is_symlink():
            raise ValueError("refusing a symlinked evidence path")
    for path in (BASE, snapshot):
        info = path.stat()
        if info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o700:
            raise ValueError("private evidence directory must be root-owned mode 0700")
    descriptor = os.open(snapshot / "session.log", os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "rb") as stream:
        info = os.fstat(stream.fileno())
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != 0
            or stat.S_IMODE(info.st_mode) != 0o600
        ):
            raise ValueError("expected a root-owned mode-0600 regular capture log")
        # Read only the tail if a graphics crash produced a large log.
        stream.seek(max(0, info.st_size - 1024 * 1024))
        return summarize(stream.read(1024 * 1024).decode("utf-8", errors="replace"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("snapshot")
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error("sudo is needed to read the private log; no host operation is performed")
    print(json.dumps(read_summary(args.snapshot), indent=2, ensure_ascii=True))


if __name__ == "__main__":
    main()
