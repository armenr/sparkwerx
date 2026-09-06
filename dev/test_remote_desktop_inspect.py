"""Private-error inspection must be read-only and must not dump raw inventory."""

import importlib.util
import json
import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location(
    "inspect_capture", ROOT / "remote-desktop/inspect-session.py"
)
inspect = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inspect)
STAMP = "20260906T135057Z-b9a45dfe19c3"


class InspectTests(unittest.TestCase):
    def test_extracts_error_type_and_location_without_source_or_raw_context(self):
        log = """private inventory that must not be printed
Traceback (most recent call last):
  File "/nix/store/abcdefgh-source/session-test.py", line 100, in worker
    secret_context = "do not print source lines"
AttributeError: object has no attribute 'is_socket'
FAIL|temporary_capture|private compositor/capture test failed; see the private log
"""
        summary = inspect.summarize(log)
        self.assertEqual(
            summary["traceback"], [{"file": "session-test.py", "line": 100, "function": "worker"}]
        )
        self.assertEqual(len(summary["errors"]), 2)
        self.assertIn("AttributeError", summary["errors"][0])
        self.assertNotIn("secret_context", json.dumps(summary))
        self.assertNotIn("private inventory", json.dumps(summary))
        self.assertFalse(summary["raw_log_printed"])

    def test_redacts_addresses_urls_paths_and_long_identifiers(self):
        message = (
            "FAIL|temporary_capture|100.70.20.30 fd12:3456::1 peer.tail123.ts.net "
            "person@example.com https://example.com/private /home/person/private "
            "/nix/store/abcdefghijklmnopqrstuvwxyzabcdef-source/session-test.py "
            "abcdefghijklmnopqrstuvwxyzABCDEF0123456789"
        )
        result = inspect.redact(message)
        for private in (
            "100.70.20.30",
            "fd12:3456::1",
            "peer.tail123.ts.net",
            "person@example.com",
            "example.com",
            "/home/person",
            "abcdefghijklmnopqrstuvwxyz",
        ):
            self.assertNotIn(private, result)
        self.assertIn("session-test.py", result)

    def test_includes_pinned_hyprutils_and_seatd_error_formats(self):
        # Hyprutils 5a7b8cf/src/cli/Logger.cpp prefixes levels without brackets.
        # These are synthetic diagnostics, not purported hardware evidence.
        lines = [
            "ERR @ 13:50:58.001 from aquamarine ]: example backend error",
            "CRIT ]: example fatal error",
            "WARN from aquamarine ]: example backend warning",
            "[ERR] example older log format",
            "00:00:00.123 [ERROR] [seatd/client.c:1] example seat error",
            "[!!WARNING!!] XDG_RUNTIME_DIR looks non-standard. Proceeding anyways...",
        ]
        summary = inspect.summarize("\n".join(lines))
        self.assertEqual(
            summary["compositor_diagnostics"], [inspect.redact(line) for line in lines]
        )

    def test_keeps_cpp_abort_reason_and_loader_or_assertion_diagnostics(self):
        lines = [
            "terminate called after throwing an instance of 'std::runtime_error'",
            "  what():  example initialization failure",
            "Bailing out, couldn't create example runtime directory",
            "Hyprland: example.cpp:1: main: Assertion 'example' failed.",
            "Hyprland: error while loading shared libraries: libexample.so: not found",
            "Hyprland: symbol lookup error: undefined symbol: example",
        ]
        summary = inspect.summarize("\n".join(lines))
        self.assertEqual(summary["compositor_diagnostics"], [line.strip() for line in lines])

    def test_native_errors_are_redacted_without_printing_normal_startup_inventory(self):
        log = "\n".join(
            [
                "DEBUG ]: runtime directory: /run/user/1000/private-instance",
                "DEBUG ]: private host inventory omitted",
                "\x1b[1;31mERR \x1b[0m]: failed at 100.70.20.30 /home/person/private",
                "WARN ]: token=private",
                "terminate called after throwing an instance of 'std::system_error'",
                "  what():  example error at peer.tail123.ts.net",
            ]
        )
        summary = inspect.summarize(log)
        excerpt = json.dumps(summary)
        for private in (
            "private-instance",
            "private host inventory",
            "100.70.20.30",
            "/home/person",
            "token=private",
            "peer.tail123.ts.net",
            "\x1b",
        ):
            self.assertNotIn(private, excerpt)
        self.assertEqual(len(summary["compositor_diagnostics"]), 4)
        self.assertIn("<sensitive error detail withheld>", summary["compositor_diagnostics"])

    def test_caps_native_excerpt_count_and_line_size(self):
        summary = inspect.summarize("\n".join(["ERR ]: " + "example " * 100] * 100))
        self.assertEqual(len(summary["compositor_diagnostics"]), 40)
        self.assertTrue(all(len(line) <= 500 for line in summary["compositor_diagnostics"]))

    def test_withholds_potential_credential_details_entirely(self):
        for key in ("token", "AUTH", "cookie", "password", "credential", "Bearer", "secret"):
            self.assertEqual(
                inspect.redact(f"ValueError: {key}=private"), "<sensitive error detail withheld>"
            )

    def test_ordinary_gpu_and_namespace_errors_remain_useful(self):
        message = "FAIL|temporary_capture|unexpected host device or IPC exposure: /dev/input"
        self.assertEqual(inspect.redact(message), message)
        summary = inspect.summarize("seatd started\nVendor: NVIDIA Corporation\n" + message)
        self.assertTrue(summary["seat_broker_started"])
        self.assertTrue(summary["compositor_vendor_seen"])

    def test_caps_excerpt_size_and_escapes_terminal_controls_when_serialized(self):
        summary = inspect.summarize("\n".join(["ValueError: \x1b[31m" + "x " * 500 + "\x07"] * 30))
        self.assertEqual(len(summary["errors"]), 12)
        self.assertTrue(all(len(line) <= 500 for line in summary["errors"]))
        self.assertNotIn("\x1b", json.dumps(summary))
        self.assertNotIn("\x07", json.dumps(summary))

    def test_rejects_paths_before_any_filesystem_read(self):
        with mock.patch.object(Path, "is_symlink") as symlink:
            for value in ("../session.log", "/etc/shadow", "latest", STAMP + "/../other"):
                with self.subTest(value=value), self.assertRaises(ValueError):
                    inspect.read_summary(value)
            symlink.assert_not_called()

    def test_rejects_symlinked_snapshot(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            mock.patch.object(inspect, "BASE", Path(directory)),
        ):
            (Path(directory) / STAMP).symlink_to(directory)
            with self.assertRaisesRegex(ValueError, "symlinked"):
                inspect.read_summary(STAMP)

    def test_reads_only_named_log_and_does_not_change_contents_or_mode(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            mock.patch.object(inspect, "BASE", Path(directory)),
        ):
            snapshot = Path(directory) / STAMP
            snapshot.mkdir(mode=0o700)
            log = snapshot / "session.log"
            log.write_text("ValueError: expected one private compositor\n")
            log.chmod(0o600)
            before = log.read_bytes(), log.stat().st_mode
            original_stat = Path.stat
            original_fstat = os.fstat

            def owned_by_root(info):
                fields = list(info)
                fields[stat.ST_UID] = 0
                return os.stat_result(fields)

            # Only fixture ownership is simulated; no root calls or host files.
            with (
                mock.patch.object(
                    Path,
                    "stat",
                    autospec=True,
                    side_effect=lambda path, **kwargs: owned_by_root(original_stat(path, **kwargs)),
                ),
                mock.patch.object(
                    os, "fstat", side_effect=lambda fd: owned_by_root(original_fstat(fd))
                ),
            ):
                result = inspect.read_summary(STAMP)
            self.assertEqual(result["errors"], ["ValueError: expected one private compositor"])
            self.assertEqual(before, (log.read_bytes(), log.stat().st_mode))
            self.assertEqual(sorted(path.name for path in snapshot.iterdir()), ["session.log"])


if __name__ == "__main__":
    unittest.main()
