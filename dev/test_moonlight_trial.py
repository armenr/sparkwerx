"""CPU tests for the temporary trial; no privileged commands or GPU access."""

import copy
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "remote-desktop" / filename)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


control = load("tested_trial_control", "trial-control.py")
session = load("tested_trial_session", "trial-session.py")
CONTEXT = {"token": "0123456789ab", "limit": 1800, "snapshot": "/private/snapshot"}


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


if __name__ == "__main__":
    unittest.main()
