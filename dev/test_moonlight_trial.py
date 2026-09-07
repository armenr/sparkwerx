"""CPU tests for the temporary trial; no privileged commands or GPU access."""

import ast
import copy
import hashlib
import importlib.util
import io
import json
import os
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "remote-desktop" / filename)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


control = load("tested_trial_control", "trial-control.py")
session = load("tested_trial_session", "trial-session.py")
network_test = load("tested_trial_network", "trial-network-test.py")
metrics = load("tested_trial_metrics", "trial-metrics.py")
CONTEXT = {"token": "0123456789ab", "limit": 1800, "snapshot": "/private/snapshot"}
NFT = os.environ.get("SPARKWERX_TEST_NFT") or shutil.which("nft")
SUNSHINE = os.environ.get("SPARKWERX_TEST_SUNSHINE")


class TrialBytecodeTests(unittest.TestCase):
    def test_real_wrapper_imports_leave_a_writable_source_tree_unchanged(self):
        # Writable copies expose missing -B even without sudo. Testing imports
        # in a read-only store as a normal user would hide the original defect.
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source"
            source.mkdir()
            for filename in (
                "trial-control.py",
                "trial-session.py",
                "trial-metrics.py",
                "session-test.py",
                "gpu-probe.py",
                "virtual-display.py",
                "sunshine-startup.py",
                "inspect-session.py",
            ):
                shutil.copyfile(ROOT / "remote-desktop" / filename, source / filename)

            def inventory():
                return {
                    str(path.relative_to(source)): (
                        hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
                    )
                    for path in source.rglob("*")
                }

            wrapper = Path(directory) / "bundle/bin/dgx-moonlight-trial"
            wrapper.parent.mkdir(parents=True)
            manifest = Path(directory) / "tools.json"
            manifest.write_text("{}")
            bash, readlink = shutil.which("bash"), shutil.which("readlink")
            self.assertIsNotNone(bash)
            self.assertIsNotNone(readlink)
            text = (ROOT / "remote-desktop/trial-wrapper.sh").read_text()
            for key, value in {
                "bash": bash,
                "readlink": readlink,
                "python": sys.executable,
                "controller": str(source / "trial-control.py"),
                "manifest": str(manifest),
            }.items():
                text = text.replace(f"@{key}@", shlex.quote(value))
            wrapper.write_text(text)
            env = os.environ.copy()
            env.pop("PYTHONDONTWRITEBYTECODE", None)
            env.pop("PYTHONPYCACHEPREFIX", None)
            before = inventory()
            result = subprocess.run(
                [bash, str(wrapper), "--help"],
                capture_output=True,
                text=True,
                cwd=directory,
                env=env,
                timeout=10,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("guardian", result.stdout)
            self.assertEqual(inventory(), before)

    def test_detached_python_commands_disable_bytecode(self):
        with mock.patch.dict(control.TOOLS, {"manifest": "/fixture/tools.json"}):
            for action in ("guardian", "worker", "cleanup"):
                argv = control.internal_command(action)
                self.assertEqual(argv[:2], [sys.executable, "-B"])
                self.assertEqual(argv[-1], action)

    def test_graphics_child_does_not_depend_on_parent_interpreter_flags(self):
        tree = ast.parse((ROOT / "remote-desktop/trial-session.py").read_text())
        launches = [
            node.args[0]
            for node in ast.walk(tree)
            if isinstance(node, ast.Call)
            and ast.unparse(node.func) == "subprocess.Popen"
            and node.args
            and isinstance(node.args[0], ast.List)
            and ast.unparse(node.args[0].elts[0]) == "sys.executable"
        ]
        self.assertEqual(len(launches), 1)
        self.assertEqual(ast.literal_eval(launches[0].elts[1]), "-B")

    def test_gate_and_network_entrypoints_disable_bytecode_before_imports(self):
        gate = (ROOT / "remote-desktop/trial-gate.nix").read_text()
        package = (ROOT / "remote-desktop/trial.nix").read_text()
        self.assertIn("exec python3 -B ${./trial-gate.py}", gate)
        self.assertIn("exec unshare --net -- python3 -B ${networkSource}/", package)


class TrialMetricsTests(unittest.TestCase):
    SAMPLE = {
        "elapsed_s": 10.0,
        "window_s": 5.0,
        "commits": 600,
        "callbacks": 600,
        "submit_fps": 120.0,
        "callback_fps": 120.0,
        "paint_mean_ms": 0.15,
        "paint_max_ms": 0.3,
    }

    def test_numeric_canvas_and_upstream_pipeline_statistics(self):
        prefix = "[2026-09-07 05:05:53.123]: "
        log = "\n".join(
            [
                "SPARKWERX_CANVAS_METRICS " + json.dumps(self.SAMPLE),
                prefix + "Info: [wlgrab] Requested frame rate [60fps]",
                prefix + "Info: [wlgrab] Requested frame rate [12000/100, approx. 120 fps]",
                prefix + "Info: CLIENT CONNECTED",
                prefix + "Debug: Frame processing latency (min/max/avg): 33.90ms/62.00ms/46.30ms",
                prefix
                + "Debug: Network: frame's overall network latency (min/max/avg): 0.10ms/1.50ms/0.25ms",
                prefix + "Info: CLIENT DISCONNECTED",
            ]
        )
        result = metrics.summarize(log)
        self.assertEqual(result["canvas"]["samples"], [self.SAMPLE])
        self.assertEqual(result["capture_requested_fps"]["samples"], [60.0, 120.0])
        self.assertEqual(result["client_connections"], 1)
        self.assertEqual(result["client_disconnections"], 1)
        self.assertEqual(
            result["host_processing_ms"]["samples"], [{"min": 33.9, "max": 62.0, "mean": 46.3}]
        )
        self.assertEqual(result["host_send_path_ms"]["samples"][0]["mean"], 0.25)
        self.assertFalse(result["raw_log_printed"])

    def test_unknown_old_logs_are_not_reported_as_zero_latency_or_a_pass(self):
        result = metrics.summarize("old log without timing instrumentation")
        self.assertEqual(result["canvas"], metrics.excerpt([]))
        self.assertEqual(result["host_processing_ms"], metrics.excerpt([]))
        self.assertNotIn("PASS", json.dumps(result))

    def test_arbitrary_data_and_malformed_numeric_records_are_not_exposed(self):
        invalid = [
            self.SAMPLE | {"credential": "do-not-print"},
            self.SAMPLE | {"submit_fps": "do-not-print"},
            self.SAMPLE | {"commits": True},
            self.SAMPLE | {"callbacks": 1.5},
            self.SAMPLE | {"paint_mean_ms": float("nan")},
            self.SAMPLE | {"paint_max_ms": float("inf")},
            self.SAMPLE | {"commits": 10**1000},
            self.SAMPLE | {"submit_fps": 30.0},
            self.SAMPLE | {"window_s": 0},
            self.SAMPLE | {"paint_max_ms": 0.01},
            [],
        ]
        log = "\n".join("SPARKWERX_CANVAS_METRICS " + json.dumps(item) for item in invalid)
        log += '\nSPARKWERX_CANVAS_METRICS {"broken"\n'
        log += "[2026-09-07 05:05:53]: Info: CLIENT CONNECTED do-not-print\n"
        log += "[2026-09-07 05:05:53]: Info: client address do-not-print\n"
        result = metrics.summarize(log)
        self.assertEqual(result["invalid_canvas_samples"], len(invalid) + 1)
        self.assertEqual(result["canvas"]["sample_count"], 0)
        self.assertEqual(result["client_connections"], 0)
        self.assertNotIn("do-not-print", json.dumps(result))

    def test_excerpt_keeps_early_baseline_and_late_samples_with_omission_count(self):
        result = metrics.excerpt(list(range(100)))
        self.assertEqual(result["samples"], list(range(6)) + list(range(94, 100)))
        self.assertEqual(result["samples_omitted"], 88)
        self.assertEqual(result["sample_count"], 100)

    def test_invalid_upstream_timings_are_ignored(self):
        prefix = "[2026-09-07 05:05:53]: Debug: "
        for payload in (
            "Frame processing latency (min/max/avg): 10ms/5ms/8ms",
            "Frame processing latency (min/max/avg): 0ms/5ms/8ms",
            "Frame processing latency (min/max/avg): 0ms/5ms/3ms secret",
            "[wlgrab] Requested frame rate [120/0, approx. 120 fps]",
            "[wlgrab] Requested frame rate [0fps]",
            "[wlgrab] Requested frame rate [100000fps]",
        ):
            result = metrics.summarize(prefix + payload)
            self.assertEqual(result["host_processing_ms"]["sample_count"], 0)
            self.assertEqual(result["capture_requested_fps"]["sample_count"], 0)

    def test_canvas_instrumentation_is_in_the_build_without_changing_damage_policy(self):
        canvas = (ROOT / "remote-desktop/trial-canvas.c").read_text()
        package = (ROOT / "remote-desktop/trial.nix").read_text()
        self.assertIn("--timing-self-test", package)
        self.assertIn("CLOCK_MONOTONIC", canvas)
        self.assertIn("wl_surface_damage_buffer(surface, 0, 0, width, height)", canvas)
        self.assertIn("CANVAS SUBMITS PER SEC", canvas)
        self.assertIn("./trial-metrics.py", package)

    def test_private_inspection_keeps_early_canvas_samples_before_sunshine_tail(self):
        with tempfile.TemporaryDirectory() as directory:
            history = Path(directory)
            snapshot = history / "20260907T050000Z-0123456789ab"
            snapshot.mkdir()
            log = snapshot / "session.log"
            log.write_text(
                "SPARKWERX_CANVAS_METRICS "
                + json.dumps(self.SAMPLE)
                + "\n"
                + "unrelated filler\n" * 80_000
                + "[2026-09-07 05:05:53]: Debug: Frame processing latency (min/max/avg): 33.90ms/62.00ms/46.30ms\n"
            )
            with (
                mock.patch.object(control, "HISTORY", history),
                mock.patch.object(control, "private_directory"),
                mock.patch.object(
                    control.os,
                    "fstat",
                    return_value=SimpleNamespace(
                        st_mode=stat.S_IFREG | 0o600, st_uid=0, st_size=log.stat().st_size
                    ),
                ),
                mock.patch.object(control, "command") as command,
                mock.patch("sys.stdout", new_callable=io.StringIO) as output,
            ):
                control.inspect()
                command.assert_not_called()
            report = json.loads(output.getvalue())
            self.assertEqual(report["performance"]["canvas"]["samples"], [self.SAMPLE])
            self.assertEqual(report["performance"]["host_processing_ms"]["sample_count"], 1)
            self.assertEqual(report["log_prefix_bytes_omitted"]["session.log"], 0)
            self.assertNotIn("unrelated filler", output.getvalue())


class TrialSunshineLogTests(unittest.TestCase):
    @unittest.skipUnless(SUNSHINE, "requires the pinned Sunshine binary from the package check")
    def test_pinned_native_logger_and_config_before_any_graphics_initialization(self):
        # In the pinned main.cpp, unknown-command dispatch returns 7 after
        # config/logging initialization but BEFORE display, GPU, input, or IP
        # startup. Exercise the real native sinks, not just the process fixture.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / "sunshine.conf"
            config.write_text(
                "".join(
                    f"{key} = {value}\n"
                    for key, value in session.configuration(root, {"address": "100.64.0.1"}).items()
                )
            )
            result = subprocess.run(
                [SUNSHINE, str(config), "--sparkwerx-check-native-logging"],
                cwd=root,
                env={"PATH": "/usr/bin:/bin", "HOME": directory, "XDG_CONFIG_HOME": directory},
                capture_output=True,
                text=True,
                timeout=10,
            )
            self.assertEqual(result.returncode, 7, result.stderr)
            # Config warnings precede logger initialization and reach stdout
            # only. Check them here rather than losing that validation when
            # readiness uses the native file instead of redirected stdout.
            self.assertNotIn("Unrecognized configurable option", result.stdout)
            native = (root / "console.log").read_text()
            marker = "Unknown command: sparkwerx-check-native-logging"
            self.assertIn(marker, native)
            self.assertIn(marker, result.stdout)
            self.assertIn("Sunshine version: 2026.516.143833", native)
            self.assertNotIn("Trying encoder", native)

    def test_native_log_stays_private_and_process_inherits_the_evidence_fd(self):
        directory = Path("/private/sunshine")
        config = session.configuration(directory, {"address": "100.64.0.1"})
        self.assertEqual(config["log_path"], str(directory / "console.log"))
        with mock.patch.object(session.subprocess, "Popen") as launch:
            session.launch_sunshine(
                {"sunshine": "/fixture/sunshine"}, directory / "sunshine.conf", {}, directory
            )
        self.assertIsNone(launch.call_args.kwargs["stdout"])
        self.assertEqual(launch.call_args.kwargs["stderr"], subprocess.STDOUT)
        self.assertEqual(launch.call_args.kwargs["stdin"], subprocess.DEVNULL)
        # The offline test must keep its original /dev/null native sink.
        self.assertEqual(session.startup.configuration(directory, "TEST")["log_path"], "/dev/null")

    def test_live_records_survive_termination_without_running_parent_cleanup(self):
        # Real unprivileged processes, no compositor or listeners. The stand-in
        # models Sunshine's flushed stdout + native file sinks. Kill the whole
        # test process group: saved records must not depend on a Python finally.
        records = (
            "[2026-09-07 05:05:53.123]: Info: CLIENT CONNECTED\n"
            "[2026-09-07 05:05:53.124]: Debug: Frame processing latency (min/max/avg): 1ms/3ms/2ms\n"
        )
        launcher = textwrap.dedent("""\
            import importlib.util, sys
            from pathlib import Path
            spec = importlib.util.spec_from_file_location("trial_log_test", sys.argv[1])
            session = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(session)
            child = session.launch_sunshine(
                {"sunshine": sys.executable}, Path(sys.argv[2]), {}, Path(sys.argv[3])
            )
            child.wait()
            """)
        for stop_signal in (signal.SIGTERM, signal.SIGKILL):
            with self.subTest(signal=stop_signal), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                fake = root / "sunshine.py"
                fake.write_text(
                    "import signal, sys\nfrom pathlib import Path\n"
                    f"records = {records!r}\n"
                    "Path('console.log').write_text(records)\n"
                    "sys.stdout.write(records)\nsys.stdout.flush()\n"
                    "Path('ready').touch()\nsignal.pause()\n"
                )
                evidence = root / "session.log"
                fd = os.open(evidence, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                with os.fdopen(fd, "wb") as stream:
                    process = subprocess.Popen(
                        [
                            sys.executable,
                            "-B",
                            "-c",
                            launcher,
                            str(ROOT / "remote-desktop/trial-session.py"),
                            str(fake),
                            directory,
                        ],
                        stdout=stream,
                        stderr=subprocess.STDOUT,
                        start_new_session=True,
                    )
                    try:
                        deadline = time.monotonic() + 5
                        while not (root / "ready").exists():
                            if process.poll() is not None or time.monotonic() >= deadline:
                                self.fail("stand-in did not become ready: " + evidence.read_text())
                            time.sleep(0.01)
                        self.assertEqual(evidence.read_text(), records)
                        self.assertEqual((root / "console.log").read_text(), records)
                        os.killpg(process.pid, stop_signal)
                        self.assertEqual(process.wait(timeout=5), -stop_signal)
                    finally:
                        # This group was created by the test, never a host unit.
                        try:
                            os.killpg(process.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        process.wait(timeout=5)
                self.assertEqual(evidence.read_text(), records)  # no shutdown duplication
                self.assertEqual(stat.S_IMODE(evidence.stat().st_mode), 0o600)
                summary = metrics.summarize(evidence.read_text())
                self.assertEqual(summary["client_connections"], 1)
                self.assertEqual(summary["host_processing_ms"]["sample_count"], 1)

    def test_inner_uses_live_logging_without_a_shutdown_copy(self):
        tree = ast.parse((ROOT / "remote-desktop/trial-session.py").read_text())
        inner = next(
            node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == "inner"
        )
        calls = [ast.unparse(node.func) for node in ast.walk(inner) if isinstance(node, ast.Call)]
        self.assertIn("launch_sunshine", calls)
        self.assertNotIn("sys.stdout.buffer.write", calls)
        self.assertNotIn("log_path.open", calls)
        self.assertIn("log_path.touch", calls)
        self.assertIn("private Sunshine log reached its size limit", ast.unparse(inner))


class TrialPolicyTests(unittest.TestCase):
    def test_online_inspection_omits_pairing_details(self):
        log = "Warning: PIN rejected 1234\nWarning: pairing code 9876\nWarning: certificate ABC\nFAIL|moonlight_trial|worker exited\n"
        result = control.without_pairing_details(log)
        self.assertEqual(result, "FAIL|moonlight_trial|worker exited")

    def test_offline_isolation_is_unchanged(self):
        offline = control.capture.unit_properties(Path("/private/result"), sunshine=True)
        trial, devices = control.HOST.worker_properties(CONTEXT)
        self.assertEqual(offline["PrivateNetwork"], "yes")
        self.assertEqual(offline["RuntimeMaxSec"], "150s")
        self.assertEqual(trial["RuntimeMaxSec"], "1790s")
        self.assertEqual(trial["BindsTo"], control.GUARD)
        self.assertEqual(trial["After"], control.GUARD)
        self.assertEqual(trial["KillMode"], "control-group")
        for key in (
            "PrivateDevices",
            "DevicePolicy",
            "ProtectHome",
            "ProtectSystem",
            "NoNewPrivileges",
            "CapabilityBoundingSet",
        ):
            self.assertEqual(offline[key], trial[key])
        self.assertNotIn("/dev/input", trial["BindPaths"])
        self.assertNotIn("/dev/uinput", devices)
        self.assertNotIn("CAP_NET_ADMIN", trial["CapabilityBoundingSet"])
        self.assertNotIn("CAP_MKNOD", trial["CapabilityBoundingSet"])

    def test_trial_configuration_is_private_encrypted_and_audio_free(self):
        config = session.configuration(Path("/private"), {"address": "100.64.0.1"})
        self.assertEqual(config["bind_address"], "100.64.0.1")
        self.assertEqual(config["address_family"], "ipv4")
        self.assertEqual(config["encoder"], "nvenc")
        for key in ("stream_audio", "controller", "native_pen_touch", "upnp", "system_tray"):
            self.assertEqual(config[key], "disabled")
        for key in ("keyboard", "mouse"):
            self.assertEqual(config[key], "enabled")
        for key in ("lan_encryption_mode", "wan_encryption_mode"):
            self.assertEqual(config[key], "2")

    def test_arbitrary_addresses_cannot_become_bind_addresses(self):
        for address in ("0.0.0.0", "::", "::1", "127.0.0.1", "192.168.0.1", "example.org"):
            with self.subTest(address=address), self.assertRaises(ValueError):
                session.configuration(Path("/private"), {"address": address})

    def test_network_shape_is_dual_stack_and_admin_is_loopback_only(self):
        shape = control.nft_shape(CONTEXT["token"])
        self.assertEqual(shape[0]["table"]["family"], "inet")
        self.assertEqual(shape[0]["table"]["comment"], "sparkwerx-trial-0123456789ab")
        self.assertEqual(shape[1]["chain"]["prio"], -20)
        self.assertEqual(shape[2]["rule"]["expr"][0]["match"]["right"], "lo")
        self.assertEqual(shape[2]["rule"]["expr"][1]["match"]["right"], 47990)
        for item in shape[3:]:
            self.assertEqual(
                item["rule"]["expr"][0]["match"]["right"], {"set": ["lo", "tailscale0"]}
            )

    def test_counters_and_handles_do_not_look_like_rule_changes(self):
        shape = control.nft_shape(CONTEXT["token"])
        observed = copy.deepcopy(shape)
        observed.insert(0, {"metainfo": {"version": "fixture"}})
        for item in observed[1:]:
            next(iter(item.values()))["handle"] = 99
        observed[3]["rule"]["expr"][2] = {"counter": {"packets": 1, "bytes": 100}}
        self.assertEqual(control.canonical(observed), shape)
        observed[-1]["rule"]["expr"][-1] = {"accept": None}
        self.assertNotEqual(control.canonical(observed), shape)

    def test_counter_normalization_preserves_unexpected_counter_changes(self):
        shape = control.nft_shape(CONTEXT["token"])
        for counter in (
            "named-counter",
            {},
            None,
            {"packets": 0, "bytes": 0, "name": "other"},
            {"packets": -1, "bytes": 0},
            {"packets": True, "bytes": 0},
        ):
            observed = copy.deepcopy(shape)
            observed[2]["rule"]["expr"][2] = {"counter": counter}
            with self.subTest(counter=counter):
                self.assertNotEqual(control.canonical(observed), shape)

    def test_network_install_uses_one_exclusive_batch(self):
        network = control.Network()
        with (
            mock.patch.object(network, "current", return_value=None),
            mock.patch.object(network, "verify") as verify,
            mock.patch.object(control, "command") as command,
            mock.patch.dict(control.TOOLS, {"nft": "/fixture/nft"}),
        ):
            network.install(CONTEXT)
        command.assert_called_once()
        batch = json.loads(command.call_args.kwargs["data"])["nftables"]
        self.assertEqual(list(batch[0]), ["create"])
        self.assertTrue(all(list(item) == ["add"] for item in batch[1:]))
        self.assertEqual(batch, control.nft_batch(CONTEXT["token"])["nftables"])
        verify.assert_called_once_with(CONTEXT)

    def test_table_collision_and_changed_rules_are_not_removed(self):
        network = control.Network()
        with (
            mock.patch.object(network, "current", return_value=[]),
            mock.patch.object(control, "command") as command,
        ):
            with self.assertRaises(RuntimeError):
                network.install(CONTEXT)
            with self.assertRaises(RuntimeError):
                network.remove(CONTEXT)
            command.assert_not_called()

    def test_firewall_query_failure_is_not_absence(self):
        with (
            mock.patch.object(control, "command", side_effect=RuntimeError("denied")),
            mock.patch.dict(control.TOOLS, {"nft": "nft"}),
        ):
            with self.assertRaises(RuntimeError):
                control.Network().current()

    def test_kernel_time_wait_is_not_a_live_listener(self):
        text = "header\n 0: 00000000:BB76 00000000:0000 06 other\n"  # port 47990
        with mock.patch.object(Path, "read_text", return_value=text):
            # No test UDP port collides with 47990.
            control.assert_ports_free()
        with mock.patch.object(Path, "read_text", return_value=text.replace(" 06 ", " 0A ")):
            with self.assertRaises(RuntimeError):
                control.assert_ports_free()

    def test_session_rejects_a_worker_outside_its_service(self):
        with mock.patch.object(Path, "read_text", return_value="0::/user.slice"):
            with self.assertRaises(RuntimeError):
                session.isolated()

    def test_canvas_has_no_shell_or_typed_text_log(self):
        canvas = (ROOT / "remote-desktop/trial-canvas.c").read_text()
        self.assertIn("key_count += state == WL_KEYBOARD_KEY_STATE_PRESSED", canvas)
        for forbidden in ("system(", "execl(", "fopen(", "socket(", "XTest", "/dev/input"):
            self.assertNotIn(forbidden, canvas)


class TrialCleanupTests(unittest.TestCase):
    def test_session_stops_before_network_removal(self):
        events = []
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state"
            state.mkdir()
            (state / "result").mkdir()
            (state / "context.json").write_text("{}")
            root = Path(directory) / "root"
            root.symlink_to("/fixture")
            context = CONTEXT | {"snapshot": directory}
            with (
                mock.patch.object(control, "STATE", state),
                mock.patch.object(control, "GCROOT", root),
                mock.patch.object(control, "context_read", return_value=context),
                mock.patch.object(
                    control,
                    "own_unit",
                    return_value={"LoadState": "loaded", "ActiveState": "inactive"},
                ),
                mock.patch.object(
                    control, "command", side_effect=lambda *a, **kw: events.append("stop")
                ),
                mock.patch.object(
                    control, "assert_ports_free", side_effect=lambda: events.append("ports-free")
                ),
                mock.patch.object(
                    control.NETWORK, "remove", side_effect=lambda _: events.append("remove-network")
                ),
                mock.patch.object(control.HOST, "snapshot", return_value={}),
                mock.patch.object(control, "read_json", return_value={}),
                mock.patch("sys.stdout", new_callable=io.StringIO),
            ):
                control.cleanup()
                control.cleanup()
            self.assertEqual(events, ["stop", "ports-free", "remove-network"])
            self.assertFalse(state.exists())
            self.assertFalse(root.is_symlink())
            self.assertTrue((Path(directory) / "finished.json").is_file())

    def test_failed_stop_does_not_remove_firewall(self):
        with (
            mock.patch.object(Path, "exists", return_value=True),
            mock.patch.object(control, "context_read", return_value=CONTEXT),
            mock.patch.object(
                control, "own_unit", return_value={"LoadState": "loaded", "ActiveState": "active"}
            ),
            mock.patch.object(control, "command", side_effect=RuntimeError("stop failed")),
            mock.patch.object(control.NETWORK, "remove") as remove,
        ):
            with self.assertRaises(RuntimeError):
                control.cleanup()
            remove.assert_not_called()

    def test_guardian_cannot_run_in_a_callers_shell(self):
        with (
            mock.patch.object(Path, "read_text", return_value="0::/user.slice"),
            mock.patch.object(control, "context_read") as context,
        ):
            with self.assertRaises(RuntimeError):
                control.guardian()
            context.assert_not_called()


@unittest.skipUnless(NFT and os.geteuid() != 0, "requires nft and an unprivileged parser process")
class TrialParserTests(unittest.TestCase):
    def check(self, batch):
        # --check never installs rules. An unprivileged process can parse the
        # entire batch but cannot initialize the kernel ruleset cache. Requiring
        # that sole error distinguishes a valid parse from a malformed policy;
        # packet behavior still needs the separate privileged container gate.
        result = subprocess.run(
            [NFT, "--check", "--json", "--file", "-"],
            input=json.dumps(batch),
            capture_output=True,
            text=True,
            timeout=10,
            env=os.environ | {"LC_ALL": "C"},
        )
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        return result.stderr.strip()

    def test_exact_generated_batch_reaches_only_the_kernel_permission_boundary(self):
        self.assertEqual(
            self.check(control.nft_batch(CONTEXT["token"])),
            "netlink: Error: cache initialization failed: Operation not permitted",
        )

    def test_original_empty_counter_is_rejected_by_the_real_parser(self):
        batch = control.nft_batch(CONTEXT["token"])
        batch["nftables"][2]["add"]["rule"]["expr"][2] = {"counter": {}}
        self.assertIn("Invalid counter reference", self.check(batch))


class TrialNetworkDiagnosticsTests(unittest.TestCase):
    def test_live_namespace_never_runs_a_diagnostic_command(self):
        with (
            mock.patch.object(network_test.os, "geteuid", return_value=0),
            mock.patch.object(network_test.os, "readlink", return_value="net:[1]"),
            mock.patch.object(network_test.subprocess, "run") as run,
        ):
            with self.assertRaises(RuntimeError):
                network_test.isolated_nft("nft", "--check")
            run.assert_not_called()

    def test_isolated_error_keeps_the_parser_diagnostic(self):
        with (
            mock.patch.object(network_test.os, "geteuid", return_value=0),
            mock.patch.object(network_test.os, "readlink", side_effect=["net:[2]", "net:[1]"]),
            mock.patch.dict(network_test.control.TOOLS, {"nft": "nft"}),
            mock.patch.object(
                network_test.subprocess,
                "run",
                return_value=subprocess.CompletedProcess([], 1, "", "Invalid counter reference"),
            ),
        ):
            with self.assertRaisesRegex(RuntimeError, "Invalid counter reference"):
                network_test.isolated_nft("nft", "--check")


if __name__ == "__main__":
    unittest.main()
