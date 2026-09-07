"""Offline capture verifier tests, including CPU-only video decoding fixtures."""

import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("frames", ROOT / "remote-desktop/sunshine-frames.py")
frames = importlib.util.module_from_spec(spec)
spec.loader.exec_module(frames)
PRESET = {"width": 3840, "height": 2160, "fps": 120}
RED = bytes([255, 0, 0]) * 64
GREEN = bytes([0, 255, 0]) * 64
CHANGING = (RED * 8 + GREEN * 8) * 2


def metadata():
    return {
        "codec": "h264",
        "frames": 32,
        "bytes": 1024,
        "capture_timestamps": 12,
        "width": 3840,
        "height": 2160,
        "requested_fps": 120,
    }


class SunshineFramesTests(unittest.TestCase):
    def test_repeated_colors_pass(self):
        self.assertEqual(
            frames.check_colors(CHANGING, 32), {"red": 16, "green": 16, "transitions": 3}
        )

    def test_dummy_static_single_transition_and_wrong_count_fail(self):
        for raw in (b"", RED * 32, bytes(32 * len(RED)), RED * 16 + GREEN * 16, CHANGING[:-1]):
            with self.subTest(size=len(raw)), self.assertRaises(ValueError):
                frames.check_colors(raw, 32)
        with self.assertRaises(ValueError):
            frames.check_colors(CHANGING, 31)

    def test_black_transition_frames_do_not_count_as_color_changes(self):
        raw = RED * 8 + bytes(len(RED) * 8) + RED * 8 + GREEN * 8
        with self.assertRaises(ValueError):
            frames.check_colors(raw, 32)

    def test_metadata_requires_real_capture_counters_and_exact_requested_mode(self):
        frames.check_metadata(metadata(), "h264", PRESET, 1024)
        for key, value in (
            ("width", 1920),
            ("height", 1080),
            ("codec", "hevc"),
            ("requested_fps", 60),
            ("bytes", 0),
            ("frames", 2),
            ("frames", 1025),
            ("capture_timestamps", 0),
            ("capture_timestamps", 33),
            ("bytes", True),
            ("extra", 1),
        ):
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                frames.check_metadata({**metadata(), key: value}, "h264", PRESET, 1024)

    def test_success_report_does_not_claim_a_transport_or_fps_test(self):
        report = frames.expected_report(PRESET, "2026.516.143833", "SPARKWERX-REMOTE")
        self.assertTrue(report["changing_frame_capture_tested"])
        self.assertFalse(report["streaming_tested"])
        self.assertNotIn("measured_fps", report)
        self.assertEqual(len(report["encoders"]), 3)

    def test_decode_rejects_wrong_stream_before_reading_pixels(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "h264.video").write_bytes(bytes(1024))
            (directory / "h264.json").write_text(json.dumps(metadata()))
            with mock.patch.object(frames.subprocess, "run") as run:
                run.return_value.stdout = (
                    b'{"streams":[{"codec_name":"hevc","width":3840,"height":2160}]}'
                )
                with self.assertRaises(ValueError):
                    frames.decode(
                        {"ffmpeg": "ffmpeg", "ffprobe": "ffprobe"}, directory, "h264", PRESET, {}
                    )
                self.assertEqual(run.call_count, 1)

    @unittest.skipUnless(
        os.environ.get("DGX_TEST_FFMPEG"), "CPU codec fixtures run in the Nix policy"
    )
    def test_real_cpu_video_decode_and_rejection_for_all_three_codecs(self):
        binary = Path(os.environ["DGX_TEST_FFMPEG"])
        tools = {name: str(binary / name) for name in ("ffmpeg", "ffprobe")}
        fixture = {"width": 64, "height": 64, "fps": 30}
        red = bytes([255, 0, 0]) * 64 * 64
        green = bytes([0, 255, 0]) * 64 * 64
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for codec, encoder in (("h264", "libx264"), ("hevc", "libx265"), ("av1", "libsvtav1")):
                with self.subTest(codec=codec):
                    video = directory / (codec + ".video")
                    options = (
                        ["-preset", "ultrafast"]
                        if codec != "av1"
                        else ["-preset", "12", "-svtav1-params", "lp=2"]
                    )
                    if codec == "hevc":
                        options += ["-x265-params", "pools=2"]
                    subprocess.run(
                        [
                            tools["ffmpeg"],
                            "-v",
                            "error",
                            "-f",
                            "rawvideo",
                            "-pix_fmt",
                            "rgb24",
                            "-s",
                            "64x64",
                            "-r",
                            "30",
                            "-i",
                            "pipe:0",
                            "-threads",
                            "2",
                            "-c:v",
                            encoder,
                            *options,
                            "-pix_fmt",
                            "yuv420p",
                            "-f",
                            frames.CODECS[codec],
                            str(video),
                        ],
                        input=(red * 8 + green * 8) * 2,
                        check=True,
                        capture_output=True,
                        timeout=20,
                    )
                    record = {
                        **metadata(),
                        "codec": codec,
                        "width": 64,
                        "height": 64,
                        "requested_fps": 30,
                        "bytes": video.stat().st_size,
                    }
                    (directory / (codec + ".json")).write_text(json.dumps(record))
                    frames.decode(tools, directory, codec, fixture, os.environ.copy())
                    # Correct codec/size alone is not enough: the exact packet
                    # count must match the decoded frames, not an advertisement.
                    record["frames"] = 31
                    (directory / (codec + ".json")).write_text(json.dumps(record))
                    with self.assertRaises(ValueError):
                        frames.decode(tools, directory, codec, fixture, os.environ.copy())


if __name__ == "__main__":
    unittest.main()
