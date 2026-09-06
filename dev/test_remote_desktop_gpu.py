"""Offline GPU-probe checks; no hardware, service, or encoder operations."""

import importlib.util
import io
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("gpu_probe", ROOT / "remote-desktop/gpu-probe.py")
gpu = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gpu)


class GpuProbeTests(unittest.TestCase):
    def setUp(self):
        self.metadata = {
            "streams": [
                {
                    "codec_name": "h264",
                    "width": 1280,
                    "height": 720,
                    "nb_read_frames": "60",
                    "r_frame_rate": "30/1",
                }
            ]
        }
        self.hashes = "\n".join(f"0, {i}, {i}, 1, 1382400, {i:032x}" for i in range(60))

    def test_matching_changing_video(self):
        gpu.verify_stream(self.metadata, self.hashes, "h264", "smoke")

    def test_rejects_empty_static_or_incomplete_capture(self):
        for hashes in ("", "\n".join(["0, 0, 0, 1, 42, " + "0" * 32] * 60), self.hashes[:-40]):
            with self.subTest(hashes=hashes[:40]), self.assertRaises(ValueError):
                gpu.verify_stream(self.metadata, hashes, "h264", "smoke")

    def test_requires_exact_codec_dimensions_and_count(self):
        for field, value in (
            ("codec_name", "hevc"),
            ("width", 1),
            ("height", 1),
            ("nb_read_frames", "59"),
            ("r_frame_rate", "10/1"),
        ):
            original = self.metadata["streams"][0][field]
            self.metadata["streams"][0][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                gpu.verify_stream(self.metadata, self.hashes, "h264", "smoke")
            self.metadata["streams"][0][field] = original

    def test_test_commands_only_use_synthetic_input_and_explicit_nvenc(self):
        for codec in gpu.CODECS:
            args = gpu.encode_command("ffmpeg", codec, "smoke", "test.mkv")
            self.assertEqual(args[args.index("-c:v") + 1], f"{codec}_nvenc")
            self.assertEqual(args[args.index("-frames:v") + 1], "60")
            self.assertEqual(args[args.index("-i") + 1], "testsrc2=size=1280x720:rate=30")
            self.assertIn("-nostdin", args)
            self.assertNotIn("x11grab", args)
        with self.assertRaises(ValueError):
            gpu.encode_command("ffmpeg", "libx264", "smoke", "test.mkv")

    def test_quality_presets_match_client_defaults(self):
        presets = json.loads((ROOT / "remote-desktop/client-presets.json").read_text())
        for name, preset in presets.items():
            self.assertEqual(
                gpu.PRESETS[name],
                (preset["width"], preset["height"], preset["fps"], preset["bitrateMbps"]),
            )

    def test_bridge_exposes_only_reviewed_libraries_and_scrubs_loader_overrides(self):
        with tempfile.TemporaryDirectory() as directory:
            with (
                mock.patch.object(
                    gpu, "trusted_driver_file", return_value=Path("/factory/library")
                ),
                mock.patch.dict(
                    gpu.os.environ,
                    {
                        "LD_PRELOAD": "bad",
                        "LD_LIBRARY_PATH": "bad",
                        "LD_AUDIT": "bad",
                        "FFREPORT": "bad",
                        "LIBGL_ALWAYS_SOFTWARE": "1",
                        "__EGL_VENDOR_LIBRARY_FILENAMES": "/foreign/vendor",
                    },
                ),
            ):
                bridge = Path(directory) / "driver"
                env = gpu.driver_bridge(bridge, "580.173.02")
            self.assertEqual(
                {p.name for p in bridge.iterdir()}, {f"{s}.so.1" for s in gpu.DRIVER_LIBRARIES}
            )
            self.assertEqual(env["LD_LIBRARY_PATH"], str(bridge))
            self.assertNotIn("LD_PRELOAD", env)
            self.assertNotIn("FFREPORT", env)
            self.assertNotIn("LD_AUDIT", env)
            self.assertNotIn("LIBGL_ALWAYS_SOFTWARE", env)
            self.assertNotIn("__EGL_VENDOR_LIBRARY_FILENAMES", env)
            self.assertEqual(env["__GL_SHADER_DISK_CACHE"], "0")
            self.assertEqual(env["CUDA_CACHE_DISABLE"], "1")
            self.assertEqual(bridge.stat().st_mode & 0o777, 0o700)

    def test_wrong_driver_version_fails_before_loading(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "libcuda.so.999.0.0"
            path.touch()
            with self.assertRaisesRegex(ValueError, "driver version"):
                gpu.trusted_driver_file(path, "libcuda", "580.173.02")

    def test_graphics_bridge_selects_only_the_private_nvidia_vendor(self):
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.object(
                gpu, "trusted_driver_file", return_value=Path("/factory/library")
            ):
                bridge = Path(directory) / "driver"
                env = gpu.driver_bridge(bridge, "580.173.02", graphics=True)
            self.assertEqual(env["__EGL_VENDOR_LIBRARY_FILENAMES"], str(bridge / "nvidia.json"))
            self.assertEqual(
                json.loads((bridge / "nvidia.json").read_text())["ICD"]["library_path"],
                str(bridge / "libEGL_nvidia.so.0"),
            )
            self.assertEqual(len(list(bridge.iterdir())), 8)

    def test_untrusted_library_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "libcuda.so.580.173.02"
            path.touch(mode=0o666)
            path.chmod(0o666)
            with self.assertRaisesRegex(ValueError, "untrusted"):
                gpu.trusted_driver_file(path, "libcuda", "580.173.02")

    def test_success_cleans_only_its_private_directory(self):
        self.run_probe_fixture(None, ["same", "same"], retained=False)

    def test_encoder_failure_checks_host_and_preserves_private_diagnostics(self):
        failure = subprocess.CalledProcessError(1, ["ffmpeg"], stderr="private error")
        self.run_probe_fixture(failure, ["same", "same"], retained=True)

    def test_timeout_checks_host_and_preserves_private_directory(self):
        self.run_probe_fixture(
            subprocess.TimeoutExpired(["ffmpeg"], 30), ["same", "same"], retained=True
        )

    def test_postflight_drift_is_not_reported_as_success(self):
        self.run_probe_fixture(None, ["before", "changed"], retained=True)

    def test_failed_postflight_keeps_diagnostics_even_after_successful_encoding(self):
        self.run_probe_fixture(None, ["before", RuntimeError("probe failed")], retained=True)

    def run_probe_fixture(self, failure, snapshots, *, retained):
        with tempfile.TemporaryDirectory() as directory:
            private = Path(directory) / "private"
            private.mkdir(mode=0o700)
            unrelated = Path(directory) / "unrelated"
            unrelated.write_text("preserve")
            output = io.StringIO()
            with (
                mock.patch.object(
                    gpu.sys,
                    "argv",
                    ["probe", "--ffmpeg-bin", "/nix/bin", "--egl-probe", "/nix/egl"],
                ),
                mock.patch.object(gpu.platform, "machine", return_value="aarch64"),
                mock.patch.object(gpu.platform, "system", return_value="Linux"),
                mock.patch.object(gpu.os, "geteuid", return_value=1000),
                mock.patch.object(gpu, "run", side_effect=["580.173.02", "PASS|egl"]),
                mock.patch.object(gpu, "host_snapshot", side_effect=snapshots) as snapshot,
                mock.patch.object(gpu.tempfile, "mkdtemp", return_value=str(private)),
                mock.patch.object(gpu, "driver_bridge", return_value={}),
                mock.patch.object(gpu, "exercise", side_effect=failure),
                mock.patch.object(gpu.sys, "stdout", output),
                mock.patch.object(gpu.sys, "stderr", output),
            ):
                if retained:
                    with self.assertRaises((RuntimeError, subprocess.SubprocessError)):
                        gpu.main()
                    self.assertNotIn("PASS|nvenc_probe", output.getvalue())
                else:
                    self.assertEqual(gpu.main(), 0)
                    self.assertIn("PASS|nvenc_probe", output.getvalue())
                self.assertEqual(snapshot.call_count, 2)
            self.assertEqual(private.exists(), retained)
            self.assertEqual(unrelated.read_text(), "preserve")
            if isinstance(failure, subprocess.CalledProcessError):
                self.assertEqual((private / "error.log").read_text(), "private error")
                self.assertNotIn("private error", output.getvalue())


if __name__ == "__main__":
    unittest.main()
