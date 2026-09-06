"""Dedicated-session display preparation; importing or rendering config has no host effects."""

import argparse
import json
import math
import re
import time

OUTPUT = "SPARKWERX-REMOTE"


def validate_preset(preset):
    for field, maximum in (("width", 3840), ("height", 2160), ("fps", 120)):
        if type(preset.get(field)) is not int or not 1 <= preset[field] <= maximum:
            raise ValueError(f"invalid virtual-display {field}")
    if preset["width"] % 2 or preset["height"] % 2:
        raise ValueError("virtual-display dimensions must be even")


def render_config(preset):
    validate_preset(preset)
    # A future supervisor must create the named output through this instance's
    # IPC socket BEFORE starting clients. exec-once alone is not a cold-start
    # dependency: it may wait for a monitor, producing a startup cycle.
    return f"""# Dedicated monitor-free test session, never the user's existing desktop.
monitor = , disable
monitor = {OUTPUT}, {preset["width"]}x{preset["height"]}@{preset["fps"]}, 0x0, 1
xwayland {{
    enabled = false
}}
misc {{
    disable_hyprland_logo = true
    disable_splash_rendering = true
    force_default_wallpaper = 0
}}
"""


def assert_dedicated_instance(instances, signature, pid):
    if not isinstance(signature, str) or not re.fullmatch(r"[A-Za-z0-9_.-]{1,200}", signature):
        raise ValueError("invalid explicit Hyprland instance signature")
    if type(pid) is not int or pid <= 1:
        raise ValueError("expected the compositor child PID")
    if not isinstance(instances, list) or any(not isinstance(item, dict) for item in instances):
        raise ValueError("invalid Hyprland instance inventory")
    matches = [item for item in instances if item.get("instance") == signature]
    if len(matches) != 1 or matches[0].get("pid") != pid:
        raise ValueError("Hyprland instance does not match the compositor child")


def validate_monitors(monitors, preset, *, ready):
    if not isinstance(monitors, list) or any(not isinstance(item, dict) for item in monitors):
        raise ValueError("invalid Hyprland monitor inventory")
    for monitor in monitors:
        if monitor.get("name") != OUTPUT and monitor.get("disabled") is not True:
            raise ValueError("another active output exists; refusing to change an existing desktop")
    outputs = [item for item in monitors if item.get("name") == OUTPUT]
    if len(outputs) > 1:
        raise ValueError("duplicate remote output")
    if not outputs:
        return False
    output = outputs[0]
    if not ready:
        raise ValueError("remote output already exists; refusing to adopt it without ownership")
    return (
        output.get("disabled") is False
        and output.get("width") == preset["width"]
        and output.get("height") == preset["height"]
        and type(output.get("refreshRate")) in (int, float)
        and abs(output["refreshRate"] - preset["fps"]) < 0.1
        and output.get("scale") == 1
    )


def prepare_output(
    control, instances, signature, pid, preset, *, timeout=15, clock=time.monotonic, wait=time.sleep
):
    """For a future dedicated-session supervisor, NOT a host activation command.

    control(signature, *args) must use an explicit --instance, a finite command
    timeout, and the child session's private runtime directory. The supervisor
    owns child lifetime, graphics permissions, capture, and rollback.
    """
    validate_preset(preset)
    if type(timeout) not in (int, float) or not math.isfinite(timeout) or not 0 < timeout <= 60:
        raise ValueError("virtual-output startup timeout must be between zero and 60 seconds")
    assert_dedicated_instance(instances(), signature, pid)
    validate_monitors(control(signature, "monitors", "all"), preset, ready=False)
    deadline = clock() + timeout
    # Creation and mode-setting failures are not retried against another
    # instance. No global environment import or physical-output reconfiguration.
    if control(signature, "output", "create", "headless", OUTPUT) != "ok":
        raise RuntimeError("virtual-output creation failed")
    try:
        while clock() < deadline:
            assert_dedicated_instance(instances(), signature, pid)
            if validate_monitors(control(signature, "monitors", "all"), preset, ready=True):
                return
            wait(0.1)
        raise TimeoutError("virtual output did not become ready at the exact requested mode")
    except BaseException:
        # Only our successfully created output may be removed, and only while
        # its original process still owns this instance. Never select instance 0.
        assert_dedicated_instance(instances(), signature, pid)
        control(signature, "output", "remove", OUTPUT)
        raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Render an inert dedicated-session config only.")
    parser.add_argument("--presets", required=True)
    parser.add_argument("--preset", required=True)
    args = parser.parse_args()
    with open(args.presets, encoding="utf-8") as stream:
        preset = json.load(stream)[args.preset]
    print(render_config(preset), end="")
