"""Saved-evidence report tests; no root, network, services, or GPU needed."""

import hashlib
import importlib.util
import json
import os
import stat
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location(
    "tested_moonlight_report", ROOT / "remote-desktop/trial-report.py"
)
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


def record(second, message, level="Info"):
    return f"[2026-09-22 21:00:{second:02d}.123]: {level}: {message}"


class ReconnectReportTests(unittest.TestCase):
    def test_three_connections_keep_order_and_times_with_pipeline_evidence(self):
        lines = [record(0, "Sunshine version: test")]
        for start in (1, 11, 21):
            lines += [
                record(start, "CLIENT CONNECTED"),
                record(start + 1, "Start capturing Video", "Debug"),
                record(start + 1, "Creating encoder [hevc_nvenc]"),
                record(start + 1, "Streaming bitrate is 100000000"),
                record(start + 2, "[wlgrab] Requested frame rate [120fps]"),
                record(
                    start + 3,
                    "Frame processing latency (min/max/avg): 30.6ms/69.7ms/46.15ms",
                    "Debug",
                ),
                record(start + 4, "CLIENT DISCONNECTED"),
                record(start + 5, "Resetting Input...", "Debug"),
                record(start + 6, "Session ended", "Debug"),
            ]
        result = report.summarize("\n".join(lines))
        events = result["timeline"]["items"]
        self.assertEqual(
            [e["log_elapsed_s"] for e in events if e["event"] == "client_connected"], [1, 11, 21]
        )
        self.assertEqual(
            [e["value"]["mean"] for e in events if e["event"] == "host_processing_ms"], [46.15] * 3
        )
        self.assertEqual(
            [e["encoder"] for e in events if e["event"] == "encoder_created"], ["hevc_nvenc"] * 3
        )
        self.assertEqual(
            [e["bps"] for e in events if e["event"] == "stream_bitrate"], [100_000_000] * 3
        )
        self.assertEqual(result["timeline"]["omitted"], 0)
        self.assertFalse(result["raw_log_printed"])

    def test_serious_middle_errors_survive_repeated_startup_diagnostics(self):
        noise = [
            record(
                0,
                "EGL: context priority set to HIGH but CAP_SYS_NICE capability is missing",
                "Warning",
            )
        ] * 200
        failures = [record(10, "Initial Ping Timeout", "Error")] * 3
        failures += [record(11, "Could not encode video packet", "Error")]
        result = report.summarize("\n".join(noise + failures + noise))
        self.assertEqual(result["errors"]["count"], 2)
        self.assertEqual(result["errors"]["items"][0]["count"], 3)
        self.assertEqual(result["errors"]["items"][0]["first_log_elapsed_s"], 10)
        self.assertEqual(result["warnings"]["items"][0]["count"], 400)

    def test_authentication_input_payload_and_addresses_are_never_emitted(self):
        lines = [
            record(0, "PIN rejected 8472", "Warning"),
            record(1, "certificate private-certificate", "Error"),
            record(2, "pairing credentials private-value", "Error"),
            record(3, "CLIENT CONNECTED untrusted-suffix"),
            record(4, "Received ping [v2] from 100.77.66.55 payload-private", "Debug"),
            record(
                5,
                "Failed sending to 100.77.66.55:48000 https://private.example/bad /home/person/private",
                "Error",
            ),
            record(6, "could not open peer.tail1234.ts.net user@example.test", "Error"),
            record(7, "CUDA failure\x1b[31m\x07", "Error"),
        ]
        result = report.summarize(
            "\n".join(lines), "FAIL|moonlight_trial|secret private-guardian-value\n"
        )
        text = json.dumps(result)
        for hidden in (
            "8472",
            "private-certificate",
            "private-value",
            "untrusted-suffix",
            "payload-private",
            "100.77.66.55",
            "private.example",
            "/home/person",
            "tail1234",
            "user@example",
            "private-guardian-value",
            "\\u0007",
        ):
            self.assertNotIn(hidden, text)
        self.assertEqual(result["sensitive_records_omitted"], 3)
        self.assertEqual(result["timeline"]["count"], 0)
        self.assertIn("<ip>", text)

    def test_unknown_logs_and_missing_statistics_stay_unknown(self):
        result = report.summarize("unrecognized old log")
        self.assertEqual(result["timeline"]["count"], 0)
        self.assertIsNone(result["canvas"]["last_elapsed_s"])
        self.assertIsNone(result["canvas"]["submit_fps_min_median_max"])

    def test_canvas_summary_includes_middle_windows_without_claiming_stream_fps(self):
        values = []
        for index, fps in enumerate((120, 30, 120), start=1):
            sample = {
                "elapsed_s": index * 5.0,
                "window_s": 5.0,
                "commits": fps * 5,
                "callbacks": fps * 5,
                "submit_fps": float(fps),
                "callback_fps": float(fps),
                "paint_mean_ms": 0.15,
                "paint_max_ms": 0.3,
            }
            values.append("SPARKWERX_CANVAS_METRICS " + json.dumps(sample))
        result = report.summarize("\n".join(values))
        self.assertEqual(result["canvas"]["submit_fps_min_median_max"], [30, 120, 120])
        self.assertEqual(result["canvas"]["last_elapsed_s"], 15)

    def test_clock_reversal_is_not_reordered_or_turned_into_duration_proof(self):
        result = report.summarize(
            record(5, "CLIENT CONNECTED") + "\n" + record(4, "CLIENT DISCONNECTED")
        )
        self.assertEqual([e["log_elapsed_s"] for e in result["timeline"]["items"]], [0, -1])
        self.assertIn("backwards", " ".join(result["notes"]))

    def test_bad_timestamps_and_huge_lines_are_counted_without_echoing_them(self):
        result = report.summarize(
            record(90, "CLIENT CONNECTED") + "\n" + "private-oversized" * 1000
        )
        self.assertEqual(result["invalid_timestamps"], 1)
        self.assertEqual(result["oversized_lines_omitted"], 1)
        self.assertNotIn("private-oversized", json.dumps(result))

    def test_large_event_and_error_reports_disclose_truncation_separately(self):
        lines = [record(0, "CLIENT CONNECTED")] * 150
        lines += [record(1, f"distinct failure {i}", "Error") for i in range(80)]
        lines += [record(2, f"distinct warning {i}", "Warning") for i in range(40)]
        result = report.summarize("\n".join(lines))
        self.assertEqual(result["timeline"]["omitted"], 22)
        self.assertEqual(result["errors"]["omitted"], 16)
        self.assertEqual(result["warnings"]["omitted"], 16)

    def test_supervisor_errors_remain_visible_without_assuming_a_crash(self):
        result = report.summarize(
            "FAIL|moonlight_trial|private session or seat broker exited\n",
            "FAIL|moonlight_trial|temporary session exited\n",
        )
        self.assertEqual(
            [e["source"] for e in result["supervisor_messages"]["items"]], ["session", "guardian"]
        )
        self.assertIn("deadline", " ".join(result["notes"]))


class PrivateEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.history = Path(self.temp.name) / "history"
        self.history.mkdir(mode=0o700)
        self.stamp = "20260922T205756Z-e1eafea49450"
        self.snapshot = self.history / self.stamp
        self.snapshot.mkdir(mode=0o700)
        self.log = self.snapshot / "session.log"
        self.log.write_text(
            record(0, "CLIENT CONNECTED") + "\n" + record(3, "Initial Ping Timeout", "Error")
        )
        self.log.chmod(0o600)
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(report, "HISTORY", self.history).start()
        fstat = os.fstat

        def root_fixture(fd):
            info = fstat(fd)
            return SimpleNamespace(st_uid=0, st_mode=info.st_mode, st_size=info.st_size)

        mock.patch.object(report.os, "fstat", side_effect=root_fixture).start()

    def inventory(self):
        return {
            str(p.relative_to(self.history)): (
                p.stat().st_mode,
                hashlib.sha256(p.read_bytes()).hexdigest(),
            )
            for p in self.history.rglob("*")
            if p.is_file()
        }

    def test_latest_and_named_read_are_identical_and_do_not_change_evidence(self):
        before = self.inventory()
        latest = report.read_report()
        named = report.read_report(self.stamp)
        self.assertEqual(latest, named)
        self.assertEqual(latest["errors"]["items"][0]["message"], "Initial Ping Timeout")
        self.assertIsNone(latest["recorded_cleanup"])
        self.assertEqual(before, self.inventory())

    def test_cleanup_returns_only_verified_boolean_fields(self):
        path = self.snapshot / "finished.json"
        path.write_text(
            json.dumps(
                {
                    "host_unchanged": True,
                    "listeners_stopped": True,
                    "network_guard_removed": False,
                    "extra": "private-data",
                }
            )
        )
        path.chmod(0o600)
        result = report.read_report()
        self.assertFalse(result["recorded_cleanup"]["network_guard_removed"])
        self.assertNotIn("private-data", json.dumps(result))
        path.write_text('{"host_unchanged":"true"}')
        with self.assertRaises(ValueError):
            report.read_report()

    def test_symlinked_files_and_snapshot_are_refused(self):
        target = self.snapshot / "actual.log"
        self.log.rename(target)
        self.log.symlink_to(target)
        with self.assertRaises(OSError):
            report.read_report()
        self.log.unlink()
        target.rename(self.log)
        other = self.history / "20260922T205757Z-e1eafea49451"
        other.symlink_to(self.snapshot)
        with self.assertRaises(ValueError):
            report.read_report(other.name)

    def test_wrong_directory_and_file_permissions_are_refused(self):
        self.snapshot.chmod(0o755)
        with self.assertRaises(ValueError):
            report.read_report()
        self.snapshot.chmod(0o700)
        self.log.chmod(0o644)
        with self.assertRaises(ValueError):
            report.read_report()

    def test_wrong_owner_and_fifo_are_refused_without_blocking(self):
        with mock.patch.object(
            report.os,
            "fstat",
            return_value=SimpleNamespace(st_uid=123, st_mode=stat.S_IFDIR | 0o700),
        ):
            with self.assertRaises(ValueError):
                report.read_report()
        self.log.unlink()
        os.mkfifo(self.log, 0o600)
        with self.assertRaises(ValueError):
            report.read_report()

    def test_path_arguments_are_refused_before_reading_anything(self):
        for name in ("../outside", str(self.snapshot), self.stamp + "\n"):
            with self.subTest(name=name), mock.patch.object(report, "private_directory") as read:
                with self.assertRaises(ValueError):
                    report.read_report(name)
                read.assert_not_called()

    def test_read_ceiling_discloses_missing_prefix(self):
        self.log.write_text("abcdefghij")
        with report.private_directory(self.snapshot) as fd:
            text, offset = report.private_file(fd, "session.log", 4)
        self.assertEqual((text, offset), ("ghij", 6))

    def test_no_saved_trial_and_missing_named_trial_fail(self):
        with self.assertRaises(FileNotFoundError):
            report.read_report("20260101T000000Z-000000000000")
        self.log.unlink()
        self.snapshot.rmdir()
        with self.assertRaises(ValueError):
            report.read_report()


if __name__ == "__main__":
    unittest.main()
