"""Private input adapter orchestration tests; never start a host service."""

import importlib.util
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "remote-desktop" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


probe = load("private_input_probe", "input-probe.py")
capture = load("private_input_capture", "session-test.py")
MARKER = "Sparkwerx session-local Wayland keyboard/pointer ready"


class InputTests(unittest.TestCase):
    def test_no_network_or_kernel_input_permission_is_added(self):
        properties = capture.unit_properties(Path("/private/result"), sunshine=True)
        self.assertEqual(properties["RuntimeMaxSec"], "150s")
        self.assertEqual(properties["PrivateNetwork"], "yes")
        self.assertEqual(properties["RestrictAddressFamilies"], "AF_UNIX AF_NETLINK")
        self.assertIn("/dev/uinput", capture.FORBIDDEN_DEVICES)
        self.assertIn("/dev/input", capture.FORBIDDEN_DEVICES)
        self.assertNotIn("/dev/uinput", properties["BindPaths"])
        self.assertNotIn("CAP_MKNOD", properties["CapabilityBoundingSet"])

    def test_report_distinguishes_private_input_from_client_streaming(self):
        report = probe.expected_report(
            capture.PRESETS["4k120"], "2026.516.143833", "SPARKWERX-REMOTE"
        )
        self.assertTrue(report["private_wayland_input_tested"])
        self.assertFalse(report["kernel_input_access"])
        self.assertFalse(report["streaming_tested"])
        self.assertFalse(report["changing_frame_capture_tested"])

    def test_adapter_has_no_kernel_or_x11_fallback(self):
        header = (ROOT / "packages/sunshine/wayland-input.hpp").read_text()
        adapter = (ROOT / "packages/sunshine/wayland-input.cpp").read_text()
        self.assertIn('outputs[0]->name != "SPARKWERX-REMOTE"', header)
        self.assertIn("outputs.size() != 1", header)
        self.assertIn("geteuid() == 0", header)
        self.assertIn("std::_Exit(70)", adapter)
        for forbidden in ("libevdev_uinput_create", "XTestFake", 'open("/dev/', "system("):
            self.assertNotIn(forbidden, header + adapter)

    def run_probe(self, directory):
        return probe.probe(
            {
                "inputReceiver": "/fixture/receiver",
                "inputExercise": "/fixture/exercise",
                "sunshineVersion": "2026.516.143833",
            },
            capture.PRESETS["4k120"],
            "SPARKWERX-REMOTE",
            {"HOME": directory},
            self.stop,
            self.isolation,
        )

    def setUp(self):
        self.stop = mock.Mock()
        self.isolation = mock.Mock()

    def test_full_receipt_is_required_after_adapter_startup(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            mock.patch.object(probe.startup, "probe") as startup,
            mock.patch.object(
                probe.startup,
                "read_log",
                side_effect=[MARKER, "READY\n", probe.RECEIPT, probe.RECEIPT],
            ),
            mock.patch.object(probe.subprocess, "Popen") as popen,
            mock.patch.object(probe.subprocess, "run") as run,
            mock.patch("sys.stdout", new_callable=io.StringIO),
        ):
            popen.return_value.wait.return_value = 0
            report = self.run_probe(directory)
        startup.assert_called_once()
        self.assertTrue(report["private_wayland_input_tested"])
        self.assertEqual(self.isolation.call_count, 2)
        run.assert_called_once()
        self.assertEqual(run.call_args.args[0], ["/fixture/exercise", "--exercise"])
        self.assertTrue(run.call_args.kwargs["check"])
        self.assertEqual(run.call_args.kwargs["timeout"], 10)
        self.stop.assert_called_once_with(popen.return_value)

    def test_missing_adapter_marker_never_sends_input(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            mock.patch.object(probe.startup, "probe"),
            mock.patch.object(probe.startup, "read_log", return_value="NVENC initialized"),
            mock.patch.object(probe.subprocess, "Popen") as popen,
            self.assertRaisesRegex(RuntimeError, "did not initialize"),
        ):
            self.run_probe(directory)
        popen.assert_not_called()

    def test_partial_receipt_stops_client_and_fails(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            mock.patch.object(probe.startup, "probe"),
            mock.patch.object(
                probe.startup, "read_log", side_effect=[MARKER, "READY\n", "keys=2", "keys=2"]
            ),
            mock.patch.object(probe.subprocess, "Popen") as popen,
            mock.patch.object(probe.subprocess, "run"),
            mock.patch("sys.stdout", new_callable=io.StringIO),
            self.assertRaisesRegex(RuntimeError, "receipt did not match"),
        ):
            popen.return_value.wait.return_value = 0
            self.run_probe(directory)
        self.stop.assert_called_once_with(popen.return_value)

    def test_startup_failure_prevents_input_exercise(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            mock.patch.object(probe.startup, "probe", side_effect=RuntimeError("no encoder")),
            mock.patch.object(probe.subprocess, "Popen") as popen,
            self.assertRaisesRegex(RuntimeError, "no encoder"),
        ):
            self.run_probe(directory)
        popen.assert_not_called()


if __name__ == "__main__":
    unittest.main()
