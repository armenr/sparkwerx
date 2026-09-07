"""Offline changing-frame test of Sunshine's unchanged video engine.

Only called in the private no-IP/no-input session. Decoding real elementary
video and finding repeated red/green changes distinguishes capture from the
upstream startup probe's dummy images. This is not a transport or FPS test.
"""

import importlib.util
import json
import subprocess
import sys
import time
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "frames_startup", Path(__file__).with_name("sunshine-startup.py")
)
startup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(startup)
CODECS = {"h264": "h264", "hevc": "hevc", "av1": "obu"}
MAX_VIDEO_BYTES = 32 * 1024 * 1024
PIXELS_PER_FRAME = 8 * 8


def expected_report(preset, version, output):
    return {
        "kind": "sunshine-offline-changing-frames",
        "version": version,
        "output": output,
        "display": preset,
        "encoders": list(startup.CODECS.values()),
        "changing_frame_capture_tested": True,
        "streaming_tested": False,
    }


def check_colors(raw, expected_frames):
    frame_bytes = PIXELS_PER_FRAME * 3
    if len(raw) != expected_frames * frame_bytes or not 20 <= expected_frames <= 1024:
        raise ValueError("decoded video frame count does not match encoded packets")
    colors = []
    for offset in range(0, len(raw), frame_bytes):
        frame = raw[offset : offset + frame_bytes]
        red, green, blue = (sum(frame[index::3]) / PIXELS_PER_FRAME for index in range(3))
        if red > 180 and green < 60 and blue < 60:
            colors.append("red")
        elif green > 180 and red < 60 and blue < 60:
            colors.append("green")
        # Transitions may contain empty compositor frames; they prove nothing.
    transitions = sum(left != right for left, right in zip(colors, colors[1:]))
    if colors.count("red") < 2 or colors.count("green") < 2 or transitions < 3:
        raise ValueError("decoded video lacks repeated red/green capture changes")
    return {"red": colors.count("red"), "green": colors.count("green"), "transitions": transitions}


def check_metadata(metadata, codec, preset, actual_bytes):
    if set(metadata) != {
        "codec",
        "frames",
        "bytes",
        "capture_timestamps",
        "width",
        "height",
        "requested_fps",
    }:
        raise ValueError("unexpected capture metadata fields")
    for name, value in metadata.items():
        if name != "codec" and type(value) is not int:
            raise ValueError("capture metadata must use integer counters")
    if (
        metadata["codec"] != codec
        or metadata["width"] != preset["width"]
        or metadata["height"] != preset["height"]
        or metadata["requested_fps"] != preset["fps"]
        or metadata["bytes"] != actual_bytes
        or not 0 < actual_bytes <= MAX_VIDEO_BYTES
        or not 20 <= metadata["frames"] <= 1024
        or not 3 <= metadata["capture_timestamps"] <= metadata["frames"]
    ):
        raise ValueError("capture metadata does not match the requested test")


def decode(tools, directory, codec, preset, env):
    video = directory / (codec + ".video")
    metadata = json.loads((directory / (codec + ".json")).read_text())
    check_metadata(metadata, codec, preset, video.stat().st_size)
    common = ["-v", "error", "-threads", "2", "-f", CODECS[codec], "-i", str(video)]
    info = subprocess.run(
        [
            tools["ffprobe"],
            *common,
            "-show_entries",
            "stream=codec_name,width,height",
            "-of",
            "json",
        ],
        env=env,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        check=True,
        timeout=8,
    )
    streams = json.loads(info.stdout).get("streams")
    if streams != [{"codec_name": codec, "width": preset["width"], "height": preset["height"]}]:
        raise ValueError("decoded stream is not the expected codec and full-resolution display")
    result = subprocess.run(
        [
            tools["ffmpeg"],
            *common,
            "-filter_threads",
            "1",
            "-vf",
            "scale=8:8:flags=area",
            "-fps_mode",
            "passthrough",
            "-pix_fmt",
            "rgb24",
            "-f",
            "rawvideo",
            "pipe:1",
        ],
        env=env,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        check=True,
        timeout=8,
    )
    colors = check_colors(result.stdout, metadata["frames"])
    # These counters enter only the root-private log, not general terminal output.
    print("INFO|sunshine_decoded_frames|" + json.dumps({**metadata, **colors}), flush=True)


def probe(tools, preset, output, env, stop, verify_isolation):
    verify_isolation()
    directory = Path(env["HOME"]) / "sunshine-frames"
    directory.mkdir(mode=0o700)
    (directory / "apps.json").write_text(json.dumps({"env": {}, "apps": []}))
    (directory / "sunshine.conf").write_text(
        "".join(
            f"{key} = {value}\n" for key, value in startup.configuration(directory, output).items()
        )
    )
    preset_name = "1440p120" if preset["width"] == 2560 else f"4k{preset['fps']}"
    log_path = directory / "console.log"
    child = None
    client = None
    try:
        with log_path.open("wb") as stream:
            child = subprocess.Popen(
                [tools["sunshineFrameCapture"], "--capture", preset_name],
                env=env,
                cwd=directory,
                stdin=subprocess.DEVNULL,
                stdout=stream,
                stderr=subprocess.STDOUT,
            )
            deadline = time.monotonic() + 60
            phase = 0
            while child.poll() is None:
                if time.monotonic() >= deadline:
                    raise TimeoutError("Sunshine changing-frame capture timed out")
                startup.read_log(log_path)  # Enforce the same private-log size limit.
                stop(client)
                client = subprocess.Popen(
                    [tools["client"], ("red", "green")[phase % 2]],
                    env=env,
                    stdin=subprocess.DEVNULL,
                )
                phase += 1
                time.sleep(0.35)
                if client.poll() is not None:
                    raise RuntimeError("changing-color client exited during capture")
            if child.returncode != 0:
                raise RuntimeError(
                    f"Sunshine offline capture exited with status {child.returncode}"
                )
        missing = startup.missing_evidence(
            startup.read_log(log_path), preset, tools["sunshineVersion"]
        )
        if missing:
            raise RuntimeError(
                "Sunshine frame test lacks encoder/display evidence: " + ", ".join(missing)
            )
        stop(client)
        client = None
        for codec in CODECS:
            decode(tools, directory, codec, preset, env)
        verify_isolation()
        return expected_report(preset, tools["sunshineVersion"], output)
    finally:
        stop(child)
        stop(client)
        if log_path.exists():
            # Enclosing service output is private and inspected through redaction.
            with log_path.open("rb") as stream:
                sys.stdout.write(
                    stream.read(startup.MAX_LOG_BYTES).decode("utf-8", errors="replace")
                )
            sys.stdout.flush()
        # Files contain only generated test colors. Never retain a screenshot or
        # video beyond the test; the private log keeps failure diagnostics.
        for codec in CODECS:
            (directory / (codec + ".video")).unlink(missing_ok=True)
