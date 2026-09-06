"""Offline checks for the temporary capture diagnostic; never launch a host unit."""

import errno
import importlib.util
import io
import json
import os
import socket
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("capture", ROOT / "remote-desktop/session-test.py")
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


class CaptureTests(unittest.TestCase):
    def test_private_ipc_paths_fit_with_the_full_upstream_instance_signature(self):
        capture.validate_ipc_path(capture.RUNTIME / "user/r")
        for runtime in (
            Path("/run/sparkwerx-session/user/runtime"),
            Path("/run/" + "x" * 80),
            Path("/run/" + "\u00e9" * 10),
        ):
            with self.subTest(runtime=runtime), self.assertRaisesRegex(ValueError, "too long"):
                capture.validate_ipc_path(runtime)

    def test_kms_uses_only_the_loaded_kernel_boolean(self):
        for value, expected in (("Y\n", True), ("N\n", False)):
            with mock.patch.object(capture, "KMS_MODESET") as parameter:
                parameter.read_text.return_value = value
                self.assertIs(capture.kms_enabled(), expected)
                parameter.read_text.assert_called_once_with(encoding="ascii")
        for value in ("", "1", "enabled", "unknown"):
            with mock.patch.object(capture, "KMS_MODESET") as parameter:
                parameter.read_text.return_value = value
                with self.assertRaisesRegex(ValueError, "unexpected"):
                    capture.kms_enabled()

    def test_unreadable_kms_state_is_not_treated_as_enabled(self):
        with mock.patch.object(capture, "KMS_MODESET") as parameter:
            parameter.read_text.side_effect = PermissionError("private kernel parameter")
            with self.assertRaises(PermissionError):
                capture.kms_enabled()

    def test_disabled_kms_stops_preflight_before_snapshots_or_any_subprocess(self):
        with (
            mock.patch.object(capture.os, "geteuid", return_value=0),
            mock.patch.object(capture.platform, "machine", return_value="aarch64"),
            mock.patch.object(capture.socket, "gethostname", return_value="sparkle-01"),
            mock.patch.object(capture, "ROOT_PROFILE") as profile,
            mock.patch.object(capture, "kms_enabled", return_value=False),
            mock.patch.object(capture, "host_snapshot") as snapshot,
            mock.patch.object(capture.subprocess, "run") as run,
            self.assertRaisesRegex(ValueError, "KMS is disabled"),
        ):
            profile.resolve.return_value = capture.PILOT
            capture.preflight()
        snapshot.assert_not_called()
        run.assert_not_called()

    def test_sunshine_checks_uvm_before_snapshot_or_any_subprocess(self):
        with (
            mock.patch.object(capture.os, "geteuid", return_value=0),
            mock.patch.object(capture.platform, "machine", return_value="aarch64"),
            mock.patch.object(capture.socket, "gethostname", return_value="sparkle-01"),
            mock.patch.object(capture, "ROOT_PROFILE") as profile,
            mock.patch.object(capture, "kms_enabled", return_value=True),
            mock.patch.object(
                capture, "validate_cuda_device", side_effect=ValueError("CUDA device absent")
            ) as validate,
            mock.patch.object(capture, "host_snapshot") as snapshot,
            mock.patch.object(capture.subprocess, "run") as run,
            self.assertRaisesRegex(ValueError, "CUDA device absent"),
        ):
            profile.resolve.return_value = capture.PILOT
            capture.preflight(sunshine=True)
        validate.assert_called_once_with()
        snapshot.assert_not_called()
        run.assert_not_called()

    def test_uvm_requires_existing_root_owned_character_node_and_current_driver_number(self):
        good = {"st_mode": stat.S_IFCHR | 0o666, "st_uid": 0, "st_rdev": os.makedev(498, 0)}
        with (
            mock.patch.object(capture, "CUDA_DEVICE") as device,
            mock.patch.object(capture, "DRIVER_DEVICES") as drivers,
        ):
            drivers.read_text.return_value = "Character devices:\n498 nvidia-uvm\n"
            device.lstat.return_value = SimpleNamespace(**good)
            capture.validate_cuda_device()
            device.lstat.assert_called_once_with()
            for changed in (
                {"st_mode": stat.S_IFREG | 0o666},
                {"st_mode": stat.S_IFLNK | 0o777},
                {"st_uid": 1000},
                {"st_rdev": os.makedev(499, 0)},
                {"st_rdev": os.makedev(498, 1)},
            ):
                with self.subTest(changed=changed), self.assertRaisesRegex(ValueError, "driver"):
                    device.lstat.return_value = SimpleNamespace(**(good | changed))
                    capture.validate_cuda_device()
            device.lstat.return_value = SimpleNamespace(**good)
            for listing in ("", "498 unrelated\n", "498 nvidia-uvm\n499 nvidia-uvm\n"):
                with self.subTest(listing=listing), self.assertRaisesRegex(ValueError, "driver"):
                    drivers.read_text.return_value = listing
                    capture.validate_cuda_device()

    def test_missing_uvm_fails_without_trying_to_create_nodes_or_load_modules(self):
        with (
            mock.patch.object(capture, "CUDA_DEVICE") as device,
            mock.patch.object(capture.subprocess, "run") as run,
            mock.patch.object(capture.subprocess, "Popen") as popen,
            self.assertRaisesRegex(ValueError, "never loads modules or creates device nodes"),
        ):
            device.lstat.side_effect = FileNotFoundError()
            capture.validate_cuda_device()
        self.assertEqual(device.mock_calls, [mock.call.lstat()])
        run.assert_not_called()
        popen.assert_not_called()

    def test_kms_check_only_reports_the_setting_and_never_starts_the_test(self):
        for enabled in (False, True):
            with (
                mock.patch.object(
                    capture.sys,
                    "argv",
                    [
                        "session-test.py",
                        "host",
                        "--tools",
                        "/not/read.json",
                        "--check-kms",
                    ],
                ),
                mock.patch.object(capture.os, "geteuid", return_value=0),
                mock.patch.object(capture.platform, "machine", return_value="aarch64"),
                mock.patch.object(capture.socket, "gethostname", return_value="sparkle-01"),
                mock.patch.object(capture, "kms_enabled", return_value=enabled),
                mock.patch.object(capture, "host") as host,
                mock.patch.object(capture.subprocess, "run") as run,
                mock.patch.object(capture.subprocess, "Popen") as popen,
                mock.patch.object(Path, "write_text") as write,
                mock.patch.object(Path, "mkdir") as mkdir,
                mock.patch.object(capture.os, "umask") as umask,
                mock.patch.object(capture.sys, "stdout", new_callable=io.StringIO) as output,
            ):
                capture.main()
            self.assertIn("KMS_STATUS=" + ("ENABLED" if enabled else "DISABLED"), output.getvalue())
            for call in (host, run, popen, write, mkdir, umask):
                call.assert_not_called()

    def test_renderer_must_be_nvidia_gb10_not_a_cpu_or_another_gpu(self):
        capture.check_renderer(
            "[DEBUG] Vendor: NVIDIA Corporation\n[DEBUG] Renderer: NVIDIA GB10/PCIe/SSE2\n"
        )
        for log in (
            "Vendor: Mesa\nRenderer: llvmpipe",
            "Vendor: NVIDIA Corporation\nRenderer: RTX 4090",
            "",
        ):
            with self.subTest(log=log), self.assertRaises(ValueError):
                capture.check_renderer(log)

    @unittest.skipUnless(
        Path("/usr/bin/systemd-analyze").exists(), "factory systemd parser unavailable"
    )
    def test_factory_systemd_accepts_the_unit_directives_without_starting_it(self):
        for sunshine in (False, True):
            with self.subTest(sunshine=sunshine), tempfile.TemporaryDirectory() as directory:
                unit = Path(directory) / "sparkwerx-capture-syntax.service"
                props = capture.unit_properties(directory, sunshine=sunshine)
                directives = [f"{key}={value}" for key, value in props.items()]
                directives += [
                    f"DeviceAllow={device} rw" for device in capture.device_nodes(sunshine=sunshine)
                ]
                unit.write_text(
                    "[Unit]\nDescription=Inert capture syntax check\n[Service]\nExecStart=/bin/true\n"
                    + "\n".join(directives)
                    + "\n"
                )
                result = subprocess.run(
                    ["/usr/bin/systemd-analyze", "verify", "--man=no", str(unit)],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("Unknown", result.stderr)
                self.assertNotIn("Failed to parse", result.stderr)

    def test_unit_has_independent_deadline_and_whole_process_tree_cleanup(self):
        props = capture.unit_properties("/private/result")
        self.assertEqual(props["RuntimeMaxSec"], "150s")
        self.assertEqual(props["TimeoutStopSec"], "5s")
        self.assertEqual(props["KillMode"], "control-group")
        self.assertEqual(props["Restart"], "no")
        self.assertEqual(props["SendSIGKILL"], "yes")
        self.assertEqual(props["LimitCORE"], "0")

    def test_unit_exposes_only_reviewed_gpu_devices_and_private_result_directory(self):
        props = capture.unit_properties("/private/result")
        self.assertEqual(props["PrivateDevices"], "yes")
        self.assertEqual(props["DevicePolicy"], "closed")
        self.assertEqual(
            props["BindPaths"].split(), [*capture.DEVICES, "/private/result:/run/sparkwerx-result"]
        )
        for device in capture.FORBIDDEN_DEVICES:
            self.assertNotIn(device, props["BindPaths"].split())

    def test_only_sunshine_gets_uvm_and_other_unit_restrictions_are_identical(self):
        base = capture.unit_properties("/private/result")
        sunshine = capture.unit_properties("/private/result", sunshine=True)
        self.assertEqual(
            capture.device_nodes(),
            (
                "/dev/dri/card1",
                "/dev/dri/renderD128",
                "/dev/nvidia0",
                "/dev/nvidiactl",
                "/dev/nvidia-modeset",
            ),
        )
        self.assertEqual(
            capture.device_nodes(sunshine=True), capture.device_nodes() + ("/dev/nvidia-uvm",)
        )
        self.assertEqual(
            sunshine.pop("BindPaths").split(),
            [*capture.device_nodes(sunshine=True), "/private/result:/run/sparkwerx-result"],
        )
        self.assertNotIn("/dev/nvidia-uvm", base.pop("BindPaths").split())
        self.assertEqual(base, sunshine)
        self.assertIn("/dev/nvidia-uvm-tools", capture.FORBIDDEN_DEVICES)

    def test_device_snapshot_includes_uvm_and_its_unexposed_tools_node(self):
        info = SimpleNamespace(st_uid=0, st_gid=0, st_mode=stat.S_IFCHR | 0o666, st_rdev=1)
        with (
            mock.patch.object(Path, "exists", return_value=True),
            mock.patch.object(Path, "stat", return_value=info),
            mock.patch.object(capture.os, "listxattr", return_value=[]),
        ):
            snapshot = capture.device_snapshot()
        self.assertEqual(snapshot["/dev/nvidia-uvm"], [0, 0, info.st_mode, 1, {}])
        self.assertEqual(snapshot["/dev/nvidia-uvm-tools"], snapshot["/dev/nvidia-uvm"])

    def test_unit_hides_host_ipc_and_denies_all_ip_socket_families(self):
        props = capture.unit_properties("/private/result")
        self.assertTrue(props["TemporaryFileSystem"].startswith("/run:"))
        self.assertEqual(props["PrivateNetwork"], "yes")
        self.assertEqual(props["RestrictAddressFamilies"].split(), ["AF_UNIX", "AF_NETLINK"])
        self.assertEqual(props["ProtectHome"], "yes")
        self.assertEqual(props["ProtectSystem"], "strict")
        self.assertEqual(props["NoNewPrivileges"], "yes")
        self.assertEqual(props["RestrictNamespaces"], "yes")

    def test_isolation_requires_all_four_tcp_udp_rejections(self):
        with (
            mock.patch.object(
                capture.socket, "socket", side_effect=OSError(errno.EPERM, "denied")
            ) as call,
            mock.patch.object(capture.os.path, "lexists", return_value=False),
            mock.patch.object(
                capture.socket, "socketpair", return_value=(mock.Mock(), mock.Mock())
            ),
        ):
            capture.verify_isolation()
        self.assertEqual(
            call.call_args_list,
            [
                mock.call(family, kind)
                for family in (socket.AF_INET, socket.AF_INET6)
                for kind in (socket.SOCK_STREAM, socket.SOCK_DGRAM)
            ],
        )

    def test_sunshine_revalidates_uvm_inside_the_private_namespace(self):
        with (
            mock.patch.object(capture.socket, "socket", side_effect=OSError(errno.EPERM, "denied")),
            mock.patch.object(capture.os.path, "lexists", return_value=False),
            mock.patch.object(
                capture.socket, "socketpair", return_value=(mock.Mock(), mock.Mock())
            ),
            mock.patch.object(capture, "validate_cuda_device") as validate,
        ):
            capture.verify_isolation(sunshine=True)
        validate.assert_called_once_with()

    def test_allowed_inet_socket_fails_before_starting_any_compositor(self):
        with (
            mock.patch.object(capture.socket, "socket", return_value=mock.Mock()),
            self.assertRaisesRegex(RuntimeError, "not denied"),
        ):
            capture.verify_isolation()

    def test_unrelated_socket_error_is_not_a_successful_rejection(self):
        with (
            mock.patch.object(
                capture.socket, "socket", side_effect=OSError(errno.EMFILE, "too many")
            ),
            self.assertRaises(OSError),
        ):
            capture.verify_isolation()

    def test_exposed_input_or_host_ipc_fails_before_startup(self):
        for path in (
            *capture.FORBIDDEN_DEVICES,
            str(capture.CUDA_DEVICE),
            "/run/systemd/private",
            "/run/dbus/system_bus_socket",
        ):
            with (
                self.subTest(path=path),
                mock.patch.object(
                    capture.socket, "socket", side_effect=OSError(errno.EPERM, "denied")
                ),
                mock.patch.object(
                    capture.os.path, "lexists", side_effect=lambda value: value == path
                ),
                self.assertRaisesRegex(RuntimeError, "exposure"),
            ):
                capture.verify_isolation()

    def test_ppm_accepts_both_colors_and_rejects_stale_frame(self):
        preset = {"width": 8, "height": 6, "fps": 120}
        hashes = []
        for name, rgb in (("red", b"\xff\0\0"), ("green", b"\0\xff\0")):
            frame = b"P6\n8 6\n255\n" + rgb * 48
            hashes.append(capture.check_ppm(frame, preset, name))
            with self.assertRaisesRegex(ValueError, "expected"):
                capture.check_ppm(frame, preset, "green" if name == "red" else "red")
        self.assertNotEqual(*hashes)

    def test_ppm_rejects_black_frames_wrong_dimensions_and_truncation(self):
        preset = {"width": 8, "height": 6, "fps": 120}
        for frame in (
            b"P3\n8 6\n255\n",
            b"P6\n8 6\n255\n" + bytes(144),
            b"P6\n6 8\n255\n" + b"\xff\0\0" * 48,
            b"P6\n8 6\n255\n" + b"\xff\0\0" * 47,
        ):
            with self.subTest(frame=frame[:15]), self.assertRaises(ValueError):
                capture.check_ppm(frame, preset, "red")

    def test_ppm_checks_multiple_regions_not_just_one_pixel(self):
        preset = {"width": 8, "height": 6, "fps": 120}
        payload = bytearray(b"\xff\0\0" * 48)
        payload[(1 * 8 + 2) * 3] = 0
        with self.assertRaises(ValueError):
            capture.check_ppm(b"P6\n8 6\n255\n" + payload, preset, "red")

    def test_config_has_no_autostart_and_disables_physical_outputs_and_xwayland(self):
        for preset in capture.PRESETS.values():
            config = capture.test_config(preset)
            self.assertIn("monitor = , disable", config)
            self.assertIn("xwayland {\n    enabled = false", config)
            self.assertIn("no_update_news = true", config)
            self.assertNotIn("exec", config)

    def test_root_compositor_is_rejected_before_device_or_session_access(self):
        with (
            mock.patch.object(capture.os, "geteuid", return_value=0),
            mock.patch.object(capture, "verify_isolation") as isolation,
            self.assertRaisesRegex(RuntimeError, "never run as root"),
        ):
            capture.capture_session({}, "4k120", "580.173.02")
        isolation.assert_not_called()

    def test_worker_cannot_be_started_directly_as_root_outside_its_transient_unit(self):
        with (
            mock.patch.object(capture.os, "geteuid", return_value=0),
            mock.patch.object(Path, "read_text", return_value="0::/user.slice/ssh.service"),
            self.assertRaisesRegex(RuntimeError, "unique transient"),
        ):
            capture.worker({}, "n0b0dy", "4k120", "580.173.02")

    def test_normal_exit_does_not_send_signals_to_reused_or_unowned_pid(self):
        child = mock.Mock()
        child.poll.return_value = 0
        capture.stop(child)
        capture.stop(None)
        child.terminate.assert_not_called()

    def test_cleanup_escalates_only_its_own_unresponsive_child(self):
        child = mock.Mock()
        child.poll.return_value = None
        child.wait.side_effect = [subprocess.TimeoutExpired("test", 3), 0]
        capture.stop(child)
        child.terminate.assert_called_once()
        child.kill.assert_called_once()

    def test_factory_bridge_scrubs_ambient_settings_and_uses_private_socket(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def fake_bridge(path, _version, **_kwargs):
                path.mkdir()
                return dict(os.environ) | {"LD_LIBRARY_PATH": str(path)}

            def resolve(path, **_kwargs):
                if path.name == "libnvidia-egl-gbm.so.1":
                    return Path("/usr/lib/aarch64-linux-gnu/libnvidia-egl-gbm.so.1.1.3")
                return path

            with (
                mock.patch.object(capture.gpu, "driver_bridge", side_effect=fake_bridge),
                mock.patch.object(
                    capture.gpu, "trusted_driver_file", side_effect=lambda path, *_: path
                ),
                mock.patch.object(Path, "resolve", autospec=True, side_effect=resolve),
                mock.patch.dict(
                    os.environ,
                    {
                        "DISPLAY": ":0",
                        "WAYLAND_DISPLAY": "host",
                        "LD_PRELOAD": "/bad",
                        "DBUS_SESSION_BUS_ADDRESS": "host",
                    },
                ),
            ):
                env = capture.session_environment(
                    root,
                    "580.173.02",
                    {
                        "libgbm.so.1": "/nix/store/test/lib/libgbm.so.1",
                        "libdrm.so.2": "/nix/store/test/lib/libdrm.so.2",
                    },
                )
            for name in ("DISPLAY", "WAYLAND_DISPLAY", "LD_PRELOAD", "DBUS_SESSION_BUS_ADDRESS"):
                self.assertNotIn(name, env)
            self.assertEqual(env["SEATD_SOCK"], "/run/seatd.sock")
            self.assertEqual(env["XDG_RUNTIME_DIR"], str(root / "r"))
            self.assertEqual(env["AQ_DRM_DEVICES"], "/dev/dri/card1")
            self.assertEqual(env["GBM_BACKENDS_PATH"], str(root / "driver"))
            self.assertEqual(env["HYPRLAND_NO_SD_VARS"], "1")
            platform_json = json.loads((root / "driver/gbm.json").read_text())
            self.assertEqual(
                platform_json["ICD"]["library_path"],
                "/usr/lib/aarch64-linux-gnu/libnvidia-egl-gbm.so.1.1.3",
            )


if __name__ == "__main__":
    unittest.main()
