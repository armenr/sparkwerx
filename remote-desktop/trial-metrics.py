"""Extract numeric trial timings; never return raw log text or client identity."""

import json
import math
import re

CANVAS_KEYS = {
    "elapsed_s",
    "window_s",
    "commits",
    "callbacks",
    "submit_fps",
    "callback_fps",
    "paint_mean_ms",
    "paint_max_ms",
}
NUMBER = r"([0-9]{1,8}(?:\.[0-9]{1,8})?)"
SUNSHINE = re.compile(r"^\[[0-9:. T+-]+\]: (?:Debug|Info): (.*)$")
LATENCY = re.compile(
    r"(Frame processing latency|Network: frame's overall network latency) "
    rf"\(min/max/avg\): {NUMBER}ms/{NUMBER}ms/{NUMBER}ms"
)


def excerpt(samples):
    return {
        "sample_count": len(samples),
        "samples": samples if len(samples) <= 12 else samples[:6] + samples[-6:],
        "samples_omitted": max(0, len(samples) - 12),
    }


def canvas_sample(text):
    try:
        value = json.loads(text)
    except (ValueError, RecursionError):
        return None
    if not isinstance(value, dict) or value.keys() != CANVAS_KEYS:
        return None
    if any(
        type(number) not in (int, float)
        or not 0 <= number <= 1_000_000
        or not math.isfinite(number)
        for number in value.values()
    ):
        return None
    if (
        not 5 <= value["window_s"] <= value["elapsed_s"]
        or type(value["commits"]) is not int
        or type(value["callbacks"]) is not int
        or value["commits"] == 0
        or value["paint_mean_ms"] > value["paint_max_ms"]
    ):
        return None
    # Printed times/rates have three decimal places. Check internal agreement
    # without treating a forged or malformed record as measured performance.
    for count, rate in (("commits", "submit_fps"), ("callbacks", "callback_fps")):
        if abs(value[count] / value["window_s"] - value[rate]) > 0.1:
            return None
    return value


def summarize(log):
    canvas, requested_fps, processing, sending = [], [], [], []
    connections = disconnections = rejected = 0
    for line in log.splitlines():
        if line.startswith("SPARKWERX_CANVAS_METRICS "):
            sample = canvas_sample(line.removeprefix("SPARKWERX_CANVAS_METRICS "))
            if sample is None:
                rejected += 1
            else:
                canvas.append(sample)
            continue
        match = SUNSHINE.fullmatch(line)
        if not match:
            continue
        payload = match[1]
        connections += payload == "CLIENT CONNECTED"
        disconnections += payload == "CLIENT DISCONNECTED"
        latency = LATENCY.fullmatch(payload)
        if latency:
            low, high, average = map(float, latency.group(2, 3, 4))
            if 0 <= low <= average <= high <= 60_000:
                target = processing if latency[1] == "Frame processing latency" else sending
                target.append({"min": low, "max": high, "mean": average})
        fps = re.fullmatch(rf"\[wlgrab\] Requested frame rate \[{NUMBER}fps\]", payload)
        fractional = re.fullmatch(
            rf"\[wlgrab\] Requested frame rate \[(\d{{1,8}})/(\d{{1,8}}), approx\. {NUMBER} fps\]",
            payload,
        )
        value = None
        if fps:
            value = float(fps[1])
        elif fractional and int(fractional[2]):
            value = int(fractional[1]) / int(fractional[2])
        if value is not None and 0 < value <= 1000:
            requested_fps.append(round(value, 3))
    return {
        "canvas": excerpt(canvas),
        "invalid_canvas_samples": rejected,
        "capture_requested_fps": excerpt(requested_fps),
        "client_connections": connections,
        "client_disconnections": disconnections,
        "host_processing_ms": excerpt(processing),
        "host_send_path_ms": excerpt(sending),
        "notes": [
            "Canvas rates measure client submissions/callbacks, not displayed or streamed FPS.",
            "Capture requests include startup probes; they are not achieved frame rates.",
            "Host processing includes the capture-timestamp-to-packet pipeline, not just NVENC.",
            "Host send-path timing is not network round-trip latency or a Tailscale path check.",
            "Sunshine timing/connection records arrive after session shutdown; absent is unknown.",
        ],
        "raw_log_printed": False,
    }
