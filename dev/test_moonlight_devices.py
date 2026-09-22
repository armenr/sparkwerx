"""Read-only GPU selection fixtures: no root, real device opens, or graphics."""

import importlib.util
import os
import stat
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "remote-desktop" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


drm = load("tested_trial_drm", "trial-devices.py")
control = load("tested_drm_control", "trial-control.py")
session = load("tested_drm_session", "trial-session.py")


class DeviceDiscoveryTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.sys_class = self.root / "sys/class/drm"
        self.dev_dri = self.root / "dev/dri"
        self.sys_class.mkdir(parents=True)
        self.dev_dri.mkdir(parents=True)
        self.nodes = {}
        self.real_lstat = Path.lstat
        self.capture = load("configured_trial_capture", "session-test.py")
        patcher = mock.patch.object(
            Path, "lstat", lambda path, *args, **kwargs: self.node_lstat(path, *args, **kwargs)
        )
        patcher.start()
        self.addCleanup(patcher.stop)

    def node_lstat(self, path, *args, **kwargs):
        if path in self.nodes:
            return self.nodes[path]
        return self.real_lstat(path, *args, **kwargs)

    def gpu(self, card="card0", render="renderD128", slot="000f:01:00.0", driver="nvidia"):
        device = self.root / "sys/devices" / slot
        device.mkdir(parents=True)
        pci = self.root / "sys/bus/pci"
        driver_path = pci / "drivers" / driver
        driver_path.mkdir(parents=True, exist_ok=True)
        (device / "subsystem").symlink_to(pci)
        (device / "driver").symlink_to(driver_path)
        (device / "vendor").write_text("0x10de\n")
        (device / "device").write_text("0x2e12\n")
        for name, minor, group in ((card, int(card[4:]), 44), (render, int(render[7:]), 993)):
            self.drm_node(name, device, minor, group)
        return device

    def drm_node(self, name, device, minor, group):
        entry = self.sys_class / name
        entry.mkdir()
        (entry / "device").symlink_to(device)
        (entry / "dev").write_text(f"226:{minor}\n")
        node = self.dev_dri / name
        node.touch()
        self.nodes[node] = SimpleNamespace(
            st_mode=stat.S_IFCHR | 0o660, st_uid=0, st_gid=group, st_rdev=os.makedev(226, minor)
        )

    def discover(self):
        return drm.discover(self.sys_class, self.dev_dri)

    def test_card_zero_and_nondefault_render_number_are_selected_by_identity(self):
        for card, render in (
            ("card0", "renderD128"),
            ("card1", "renderD129"),
            ("card7", "renderD135"),
        ):
            with self.subTest(card=card):
                self.gpu(card, render)
                result = self.discover()
                self.assertEqual(result["card"], str(self.dev_dri / card))
                self.assertEqual(result["render"], str(self.dev_dri / render))
                # Remove only this test's fixture entries before the next case.
                for entry in self.sys_class.iterdir():
                    (entry / "device").unlink()
                    (entry / "dev").unlink()
                    entry.rmdir()
                device = Path(result["pci_device"])
                for path in device.iterdir():
                    path.unlink()
                device.rmdir()

    def test_other_driver_and_connector_entries_do_not_select_a_gpu(self):
        self.gpu("card1")
        self.gpu("card0", "renderD129", slot="0000:00:00.0", driver="simpledrm")
        (self.sys_class / "card1-HDMI-A-1").mkdir()
        self.assertEqual(self.discover()["card"], str(self.dev_dri / "card1"))

    def test_no_nvidia_and_ambiguous_nvidia_cards_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "exactly one NVIDIA"):
            self.discover()
        self.gpu()
        self.gpu("card1", "renderD129", slot="000f:02:00.0")
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            self.discover()

    def test_wrong_vendor_device_or_bus_is_rejected(self):
        device = self.gpu()
        for field, value in (("vendor", "0x8086"), ("device", "0xffff")):
            with self.subTest(field=field):
                original = (device / field).read_text()
                (device / field).write_text(value)
                with self.assertRaisesRegex(ValueError, "GB10 PCI"):
                    self.discover()
                (device / field).write_text(original)
        (device / "subsystem").unlink()
        (device / "subsystem").symlink_to(device)
        with self.assertRaisesRegex(ValueError, "GB10 PCI"):
            self.discover()

    def test_render_node_on_another_gpu_is_not_paired(self):
        self.gpu()
        other = self.root / "different-gpu"
        other.mkdir()
        link = self.sys_class / "renderD128/device"
        link.unlink()
        link.symlink_to(other)
        with self.assertRaisesRegex(ValueError, "same GPU"):
            self.discover()

    def test_duplicate_render_nodes_are_rejected(self):
        device = self.gpu()
        self.drm_node("renderD129", device, 129, 993)
        with self.assertRaisesRegex(ValueError, "one matching render"):
            self.discover()

    def test_device_type_owner_and_kernel_number_must_match(self):
        self.gpu()
        for name in ("card0", "renderD128"):
            info = self.nodes[self.dev_dri / name]
            for field, value in (
                ("st_mode", stat.S_IFREG | 0o660),
                ("st_mode", stat.S_IFLNK | 0o777),
                ("st_uid", 1000),
                ("st_rdev", os.makedev(226, 33)),
            ):
                with self.subTest(name=name, field=field):
                    original = getattr(info, field)
                    setattr(info, field, value)
                    with self.assertRaisesRegex(ValueError, "root-owned device matching sysfs"):
                        self.discover()
                    setattr(info, field, original)

    def test_missing_device_and_invalid_sysfs_number_are_rejected(self):
        self.gpu()
        node = self.dev_dri / "card0"
        node.unlink()
        del self.nodes[node]
        with self.assertRaisesRegex(ValueError, "node is missing"):
            self.discover()
        node.touch()
        (self.sys_class / "card0/dev").write_text("1:3\n")
        with self.assertRaisesRegex(ValueError, "number is unexpected"):
            self.discover()

    def test_configure_pins_selection_and_preserves_child_only_permissions(self):
        self.gpu()
        selection = self.discover()
        with mock.patch.object(drm, "discover", return_value=selection):
            drm.configure(self.capture)
            self.assertEqual(self.capture.user_device_groups(sunshine=True), [44, 993])
            self.assertEqual(self.capture.user_device_groups(), [993])
            self.assertEqual(
                self.capture.device_nodes(sunshine=True)[:2],
                (selection["card"], selection["render"]),
            )
            self.assertIn("/dev/input", self.capture.FORBIDDEN_DEVICES)
            self.assertIn("/dev/nvidia-uvm-tools", self.capture.FORBIDDEN_DEVICES)
            self.assertNotIn(selection["card"], self.capture.FORBIDDEN_DEVICES)
            self.assertEqual(drm.configure(self.capture, expected=selection), selection)
            with self.assertRaisesRegex(ValueError, "saved trial context"):
                drm.configure(self.capture, expected=None)
            with self.assertRaisesRegex(ValueError, "saved trial context"):
                drm.configure(self.capture, expected=selection | {"card": "/dev/dri/card99"})
        with mock.patch.object(drm, "discover", return_value=selection | {"card_rdev": [226, 9]}):
            with self.assertRaisesRegex(ValueError, "changed during the trial"):
                drm.configure(self.capture)

    def test_private_namespace_may_contain_only_the_exact_pair(self):
        self.gpu()
        selection = self.discover()
        with mock.patch.object(drm, "discover", return_value=selection):
            drm.configure(self.capture)
            drm.verify_private(self.capture)
            (self.dev_dri / "card2").touch()
            with self.assertRaisesRegex(RuntimeError, "other than the selected"):
                drm.verify_private(self.capture)

    def test_worker_binding_and_compositor_environment_use_the_saved_pair(self):
        self.gpu()
        selection = self.discover()
        with (
            mock.patch.object(control, "capture", self.capture),
            mock.patch.object(control.drm, "discover", return_value=selection),
        ):
            properties, nodes = control.HOST.worker_properties(
                {"drm": selection, "token": "0123456789ab", "limit": 1800, "snapshot": "/private"}
            )
        self.assertIn(selection["card"], properties["BindPaths"].split())
        self.assertIn(selection["render"], nodes)
        self.assertNotIn("/dev/dri/card1", nodes)
        self.assertEqual(properties["PrivateDevices"], "yes")
        self.assertEqual(properties["DevicePolicy"], "closed")
        with (
            mock.patch.object(session, "capture", self.capture),
            mock.patch.object(
                self.capture,
                "session_environment",
                return_value={
                    "AQ_DRM_DEVICES": "/dev/dri/card1",
                    "LD_LIBRARY_PATH": "/private/driver",
                },
            ),
        ):
            env = session.session_environment(Path("/private"), "580.173.02", {})
        self.assertEqual(env["AQ_DRM_DEVICES"], selection["card"])
        self.assertEqual(env["LD_LIBRARY_PATH"], "/private/driver")


class TrialPreflightTests(unittest.TestCase):
    @contextmanager
    def ready(self):
        capture = load("preflight_trial_capture", "session-test.py")

        def text(argv):
            if argv[1] == "list-units":
                return "[]"
            return "inactive" if argv[2] in ("gdm.service", "dgx-dashboard.service") else "active"

        with (
            mock.patch.object(drm.os, "geteuid", return_value=0),
            mock.patch.object(capture.platform, "machine", return_value="aarch64"),
            mock.patch.object(capture.socket, "gethostname", return_value="sparkle-01"),
            mock.patch.object(
                capture, "ROOT_PROFILE", mock.Mock(resolve=lambda **kw: capture.PILOT)
            ),
            mock.patch.object(capture, "kms_enabled", return_value=True),
            mock.patch.object(drm, "configure") as configure,
            mock.patch.object(capture, "validate_cuda_device"),
            mock.patch.object(capture, "user_device_groups"),
            mock.patch.object(capture, "host_snapshot", return_value={"units_profile": [""]}),
            mock.patch.object(capture, "text", side_effect=text),
            mock.patch.object(drm.os.path, "lexists", return_value=False),
            mock.patch.object(Path, "glob", return_value=[]),
            mock.patch.object(Path, "stat", return_value=SimpleNamespace(st_mode=stat.S_IFCHR)),
        ):
            yield capture, configure

    def test_healthy_host_discovers_before_checking_group_access(self):
        with self.ready() as (capture, configure):
            capture.user_device_groups.side_effect = lambda **kw: configure.assert_called_once_with(
                capture
            )
            self.assertEqual(drm.preflight(capture), {"units_profile": [""]})
            capture.validate_cuda_device.assert_called_once_with()
            capture.user_device_groups.assert_called_once_with(sunshine=True)

    def test_kms_off_stops_before_discovery(self):
        with self.ready() as (capture, configure):
            capture.kms_enabled.return_value = False
            with self.assertRaisesRegex(ValueError, "KMS is disabled"):
                drm.preflight(capture)
            configure.assert_not_called()

    def test_host_identity_profile_unit_and_guard_gates_remain(self):
        for field in (
            "user",
            "architecture",
            "hostname",
            "profile",
            "reload",
            "unit",
            "guard",
            "recovery",
        ):
            with self.subTest(field=field), self.ready() as (capture, _):
                if field == "user":
                    drm.os.geteuid.return_value = 1000
                elif field == "architecture":
                    capture.platform.machine.return_value = "x86_64"
                elif field == "hostname":
                    capture.socket.gethostname.return_value = "another-host"
                elif field == "profile":
                    capture.ROOT_PROFILE = mock.Mock(resolve=lambda **kw: "/wrong-profile")
                elif field == "reload":
                    capture.host_snapshot.return_value = {"units_profile": ["NeedDaemonReload=yes"]}
                elif field == "unit":
                    capture.text.side_effect = lambda argv: "inactive"
                elif field == "guard":
                    drm.os.path.lexists.return_value = True
                elif field == "recovery":
                    original = capture.text.side_effect
                    capture.text.side_effect = lambda argv: (
                        '[{"unit":"dgx-any-rollback.service","active":"active"}]'
                        if argv[1] == "list-units"
                        else original(argv)
                    )
                with self.assertRaises(ValueError):
                    drm.preflight(capture)

    def test_existing_compositor_and_missing_gpu_node_still_stop_launch(self):
        with self.ready() as (capture, _):
            with mock.patch.object(
                Path, "glob", return_value=[mock.Mock(read_text=lambda: "Hyprland\n")]
            ):
                with self.assertRaisesRegex(ValueError, "existing compositor"):
                    drm.preflight(capture)
            with mock.patch.object(
                Path, "stat", return_value=SimpleNamespace(st_mode=stat.S_IFREG)
            ):
                with self.assertRaisesRegex(ValueError, "GPU device is missing"):
                    drm.preflight(capture)


class TrialChildSelectionTests(unittest.TestCase):
    def test_root_worker_and_user_child_revalidate_context_before_device_access(self):
        selection = {"card": "/dev/dri/card0", "render": "/dev/dri/renderD128"}
        for uid in (0, 1000):
            with (
                self.subTest(uid=uid),
                mock.patch.object(
                    Path,
                    "read_text",
                    side_effect=[
                        "0::/system.slice/sparkwerx-moonlight-session.service\n",
                        "CapEff:\t0000000000000000\n",
                    ],
                ),
                mock.patch.object(session.drm, "configure") as configure,
                mock.patch.object(session.drm, "verify_private") as private,
                mock.patch.object(session.os.path, "lexists", return_value=False),
                mock.patch.object(session.os, "geteuid", return_value=uid),
                mock.patch.object(session.capture, "validate_cuda_device") as cuda,
                mock.patch.object(session.capture, "verify_user_device_access") as access,
            ):
                session.isolated(selection)
                configure.assert_called_once_with(session.capture, expected=selection)
                private.assert_called_once_with(session.capture)
                cuda.assert_called_once_with()
                self.assertEqual(access.call_count, int(uid != 0))

    def test_mismatched_context_stops_worker_before_starting_any_process(self):
        with (
            mock.patch.object(session, "small_json", return_value={"drm": {}}),
            mock.patch.object(
                Path, "read_text", return_value="0::/sparkwerx-moonlight-session.service"
            ),
            mock.patch.object(
                session.drm, "configure", side_effect=ValueError("selection mismatch")
            ),
            mock.patch.object(session.subprocess, "Popen") as launch,
        ):
            with self.assertRaisesRegex(ValueError, "selection mismatch"):
                session.worker({}, Path("/fixture"))
            launch.assert_not_called()


if __name__ == "__main__":
    unittest.main()
