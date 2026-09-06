"""Offline Sunshine startup checks; do not launch a GPU, service, or listener."""

import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location(
    "startup", ROOT / "remote-desktop/sunshine-startup.py"
)
startup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(startup)

PRESET = {"width": 3840, "height": 2160, "fps": 120}
VERSION = "2026.516.143833"
OUTPUT = "SPARKWERX-REMOTE"
LOG = "\n".join(
    (
        "Sunshine version: " + VERSION,
        "Screencasting with Wayland's protocol",
        "[wlgrab] Selected monitor [private test display] for streaming",
        "[wlgrab] Resolution: 3840x2160",
        "Found H.264 encoder: h264_nvenc [nvenc]",
        "Found HEVC encoder: hevc_nvenc [nvenc]",
        "Found AV1 encoder: av1_nvenc [nvenc]",
    )
)


class SunshineStartupTests(unittest.TestCase):
    @unittest.skipUnless(
        os.environ.get("DGX_TEST_SUNSHINE"), "Sunshine parser runs in its Nix policy build"
    )
    def test_real_pinned_parser_accepts_config_and_detects_an_unknown_option(self):
        # --version dispatches after config parsing but before display, input,
        # GPU, HTTP, or server initialization in this reviewed Sunshine release.
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "apps.json").write_text('{"env": {}, "apps": []}')
            config = directory / "sunshine.conf"
            contents = "".join(
                f"{key} = {value}\n"
                for key, value in startup.configuration(directory, OUTPUT).items()
            )
            for unknown in (False, True):
                config.write_text(
                    contents + ("sparkwerx_unknown_option = test\n" if unknown else "")
                )
                result = subprocess.run(
                    [os.environ["DGX_TEST_SUNSHINE"], str(config), "--version"],
                    env={
                        "HOME": str(directory),
                        "XDG_CONFIG_HOME": str(directory / "config"),
                        "LANG": "C",
                    },
                    cwd=directory,
                    stdin=subprocess.DEVNULL,
                    capture_output=True,
                    text=True,
                    timeout=10,
                    check=True,
                )
                log = result.stdout + result.stderr
                self.assertIn("Sunshine version: " + VERSION, log)
                self.assertNotIn("Failed to apply config", log)
                self.assertEqual("Unrecognized configurable option" in log, unknown, log)
                self.assertNotIn("Trying encoder", log)
                self.assertNotIn("Screencasting", log)

    def test_config_disables_input_audio_discovery_display_changes_and_tray(self):
        config = startup.configuration(Path("/private"), OUTPUT)
        for name in (
            "keyboard",
            "mouse",
            "controller",
            "native_pen_touch",
            "stream_audio",
            "install_steam_audio_drivers",
            "system_tray",
            "upnp",
            "notify_pre_releases",
            "dd_configuration_option",
        ):
            self.assertEqual(config[name], "disabled", name)
        self.assertEqual(config["capture"], "wlr")
        self.assertEqual(config["encoder"], "nvenc")
        self.assertEqual(config["output_name"], OUTPUT)
        self.assertEqual(config["bind_address"], "127.0.0.1")
        self.assertEqual(config["origin_web_ui_allowed"], "pc")
        self.assertEqual(config["log_path"], "/dev/null")
        self.assertNotIn("global_prep_cmd", config)
        for key in ("file_apps", "file_state", "credentials_file", "pkey", "cert"):
            self.assertTrue(config[key].startswith("/private/"))

    def test_output_name_cannot_inject_configuration(self):
        for name in ("", "monitor\nupnp = enabled", "A\r\n", "../OTHER"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                startup.configuration(Path("/private"), name)

    def test_success_requires_display_backend_dimensions_version_and_all_three_final_encoders(self):
        self.assertEqual(startup.missing_evidence(LOG, PRESET, VERSION), [])
        for line in LOG.splitlines():
            with self.subTest(line=line):
                self.assertTrue(startup.missing_evidence(LOG.replace(line, ""), PRESET, VERSION))
        for log in ("", "Trying encoder [nvenc]", "Encoder [nvenc] failed"):
            self.assertTrue(startup.missing_evidence(log, PRESET, VERSION))

    def test_wrong_version_prefix_is_not_accepted(self):
        for version in (VERSION + "0", "2026.516.14383", "2025.1.1"):
            self.assertIn(
                "package version",
                startup.missing_evidence(LOG.replace(VERSION, version), PRESET, VERSION),
            )

    def test_unknown_options_software_fallback_and_other_display_size_fail(self):
        for log in (
            LOG + "\nWarning: Unrecognized configurable option [keyboard]",
            LOG + "\nFound H.264 encoder: libx264 [software]",
            LOG.replace("3840x2160", "3840x21600"),
            LOG + "\n[wlgrab] Resolution: 1920x1080",
        ):
            with self.subTest(log=log), self.assertRaises(RuntimeError):
                startup.missing_evidence(log, PRESET, VERSION)

    def test_success_report_never_claims_changing_frames_or_streaming(self):
        report = startup.expected_report(PRESET, VERSION, OUTPUT)
        self.assertEqual(report["kind"], "sunshine-startup-only")
        self.assertFalse(report["changing_frame_capture_tested"])
        self.assertFalse(report["streaming_tested"])
        self.assertNotIn("measured_fps", report)
        self.assertLess(len(json.dumps(report)), 1024)

    def test_log_size_limit_rejects_an_oversized_log(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "log"
            path.write_bytes(b"x" * (startup.MAX_LOG_BYTES + 1))
            with self.assertRaisesRegex(RuntimeError, "size limit"):
                startup.read_log(path)

    def run_probe(self, log, *, isolation_error=None, alive=False):
        with tempfile.TemporaryDirectory() as directory:
            tools = {"sunshine": "/nix/store/test/bin/sunshine", "sunshineVersion": VERSION}
            env = {"HOME": directory, "WAYLAND_DISPLAY": "wayland-1"}
            child = mock.Mock()
            child.poll.return_value = None if alive else 1

            def start(command, **kwargs):
                self.assertEqual(command[0], tools["sunshine"])
                self.assertEqual(kwargs["env"], env)
                self.assertEqual(kwargs["stdin"], subprocess.DEVNULL)
                self.assertEqual(kwargs["stderr"], subprocess.STDOUT)
                self.assertEqual(
                    json.loads((kwargs["cwd"] / "apps.json").read_text()), {"env": {}, "apps": []}
                )
                kwargs["stdout"].write(log.encode())
                kwargs["stdout"].flush()
                return child

            stop = mock.Mock()
            isolation = mock.Mock(side_effect=isolation_error)
            with (
                mock.patch.object(startup.subprocess, "Popen", side_effect=start) as popen,
                mock.patch.object(startup.time, "monotonic", side_effect=(0, 61)),
                mock.patch.object(startup.sys, "stdout", new_callable=io.StringIO),
            ):
                try:
                    return startup.probe(tools, PRESET, OUTPUT, env, stop, isolation)
                finally:
                    if isolation_error:
                        popen.assert_not_called()
                        stop.assert_not_called()
                    else:
                        stop.assert_called_once_with(child)

    def test_success_stops_server_even_if_it_already_exited_on_denied_sockets(self):
        report = self.run_probe(LOG + "\nError: Couldn't bind RTSP server: Permission denied")
        self.assertEqual(report, startup.expected_report(PRESET, VERSION, OUTPUT))

    def test_early_exit_and_timeout_stop_server_without_a_success_report(self):
        with self.assertRaisesRegex(RuntimeError, "startup lacks"):
            self.run_probe("Trying encoder [nvenc]")
        with self.assertRaisesRegex(TimeoutError, "timed out"):
            self.run_probe("Trying encoder [nvenc]", alive=True)

    def test_failed_isolation_never_starts_sunshine_or_writes_configuration(self):
        with self.assertRaisesRegex(RuntimeError, "network socket"):
            self.run_probe("", isolation_error=RuntimeError("network socket not denied"))


@unittest.skipIf(os.geteuid() == 0, "the operator deliberately rejects root invocation")
class SunshineWrapperTests(unittest.TestCase):
    def run_wrapper(self, *, metadata="false", eval_status=0, args=()):
        # Exercise the real front door with only local command doubles. No
        # Nix build, privilege request, GPU, listener, or host state is touched.
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            scripts = directory / "scripts"
            commands = directory / "commands"
            scripts.mkdir()
            commands.mkdir()
            wrapper = scripts / "test-remote-desktop-sunshine.sh"
            shutil.copyfile(ROOT / "scripts/test-remote-desktop-sunshine.sh", wrapper)
            command_source = (
                f"#!{sys.executable}\n"
                + """
import json
import os
import sys
from pathlib import Path
name = Path(sys.argv[0]).name
with open(os.environ['CALLS_FILE'], 'a') as stream:
    stream.write(json.dumps([name, *sys.argv[1:]]) + '\\n')
if name == 'nix':
    if '--apply' in sys.argv:
        print(os.environ['BUILD_METADATA'])
        sys.exit(int(os.environ['EVAL_STATUS']))
    if 'eval' in sys.argv:
        print('/nix/store/fake-private-bundle')
elif name == 'sudo':
    sys.exit(73)
elif name == 'test-remote-desktop-session.sh':
    sys.exit(74)
"""
            )
            for path in (
                commands / "nix",
                commands / "sudo",
                scripts / "test-remote-desktop-session.sh",
            ):
                path.write_text(command_source)
                path.chmod(0o700)
            calls = directory / "calls.jsonl"
            result = subprocess.run(
                [shutil.which("bash"), str(wrapper), *args],
                env={
                    **os.environ,
                    "PATH": str(commands) + os.pathsep + os.environ["PATH"],
                    "CALLS_FILE": str(calls),
                    "BUILD_METADATA": metadata,
                    "EVAL_STATUS": str(eval_status),
                },
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
            events = [json.loads(line) for line in calls.read_text().splitlines()]
            return result, events

    def test_incompatible_or_unknown_build_never_reaches_build_or_sudo(self):
        for metadata in ("false", "", "null", "unexpected"):
            with self.subTest(metadata=metadata):
                result, events = self.run_wrapper(metadata=metadata)
                self.assertEqual(result.returncode, 1)
                self.assertIn("FAIL|sunshine_build|", result.stderr)
                self.assertEqual(len(events), 1)
                self.assertEqual(events[0][0], "nix")
                self.assertIn("eval", events[0])
                self.assertNotIn("build", events[0])

    def test_failed_evaluation_does_not_accept_partial_true_output(self):
        result, events = self.run_wrapper(metadata="true", eval_status=42)
        self.assertEqual(result.returncode, 42)
        self.assertEqual(len(events), 1)

    def test_required_cuda_flags_allow_the_existing_isolated_launcher(self):
        result, events = self.run_wrapper(metadata="true")
        self.assertEqual(result.returncode, 73)  # Stub sudo only, never real sudo.
        self.assertEqual([event[0] for event in events], ["nix", "nix", "nix", "sudo"])
        self.assertIn("build", events[1])
        self.assertIn(".#remote-desktop-sunshine-startup-policy", events[1])
        self.assertEqual(events[3][1], "--")
        self.assertEqual(
            events[3][2],
            "/nix/store/fake-private-bundle/bin/dgx-remote-desktop-sunshine-startup-test",
        )

    def test_read_only_inspect_still_delegates_without_checking_cuda(self):
        result, events = self.run_wrapper(args=("inspect", "20260906T192101Z-a64914fe0711"))
        self.assertEqual(result.returncode, 74)
        self.assertEqual(
            events,
            [["test-remote-desktop-session.sh", "inspect", "20260906T192101Z-a64914fe0711"]],
        )


if __name__ == "__main__":
    unittest.main()
