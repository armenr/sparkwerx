"""Virtual-output orchestration tests with a fake compositor, never a live session."""

import importlib.util
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location(
    "virtual_display", ROOT / "remote-desktop/virtual-display.py"
)
display = importlib.util.module_from_spec(spec)
spec.loader.exec_module(display)


class FakeCompositor:
    def __init__(self):
        self.inventory = []
        self.calls = []
        self.signature = "dedicated-test-123"
        self.pid = 123
        self.create_result = "ok"
        self.ready = True
        self.now = 0

    def instances(self):
        return [{"instance": self.signature, "pid": self.pid}]

    def clock(self):
        return self.now

    def wait(self, seconds):
        self.now += seconds

    def control(self, signature, *args):
        if signature != self.signature:
            raise AssertionError("wrong instance")
        self.calls.append(args)
        if args == ("monitors", "all"):
            return self.inventory
        if args == ("output", "create", "headless", display.OUTPUT):
            if self.create_result == "ok" and self.ready:
                self.inventory = [
                    {
                        "name": display.OUTPUT,
                        "disabled": False,
                        "width": 2560,
                        "height": 1440,
                        "refreshRate": 120.0,
                        "scale": 1,
                    }
                ]
            return self.create_result
        if args == ("output", "remove", display.OUTPUT):
            self.inventory = []
            return "ok"
        raise AssertionError(args)


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.compositor = FakeCompositor()
        self.preset = {"width": 2560, "height": 1440, "fps": 120}

    def prepare(self):
        display.prepare_output(
            self.compositor.control,
            self.compositor.instances,
            "dedicated-test-123",
            123,
            self.preset,
            timeout=0.3,
            clock=self.compositor.clock,
            wait=self.compositor.wait,
        )

    def test_inert_config_has_no_autostart_or_portal(self):
        config = display.render_config(self.preset)
        self.assertIn("monitor = SPARKWERX-REMOTE, 2560x1440@120, 0x0, 1", config)
        self.assertNotIn("exec", config)
        self.assertNotIn("sunshine", config)
        self.assertIn("enabled = false", config)

    def test_success_only_touches_dedicated_virtual_output(self):
        self.prepare()
        self.assertIn(("output", "create", "headless", display.OUTPUT), self.compositor.calls)
        self.assertNotIn(("output", "remove", display.OUTPUT), self.compositor.calls)

    def test_refuses_ambient_instance_or_changed_pid_before_mutation(self):
        for field, value in (("signature", "other"), ("pid", 124)):
            setattr(self.compositor, field, value)
            with self.assertRaises(ValueError):
                self.prepare()
            self.assertEqual(self.compositor.calls, [])
            self.compositor = FakeCompositor()

    def test_refuses_existing_physical_or_virtual_output(self):
        for name in ("DP-1", display.OUTPUT):
            self.compositor.inventory = [{"name": name, "disabled": False}]
            with self.assertRaises(ValueError):
                self.prepare()
            self.assertTrue(all(call == ("monitors", "all") for call in self.compositor.calls))

    def test_missing_display_times_out_and_removes_only_its_output(self):
        self.compositor.ready = False
        with self.assertRaises(TimeoutError):
            self.prepare()
        self.assertEqual(self.compositor.calls[-1], ("output", "remove", display.OUTPUT))

    def test_failed_creation_does_not_claim_or_remove_an_output(self):
        self.compositor.create_result = "no backend"
        with self.assertRaises(RuntimeError):
            self.prepare()
        self.assertNotIn(("output", "remove", display.OUTPUT), self.compositor.calls)

    def test_changed_instance_after_creation_is_never_removed(self):
        self.compositor.ready = False
        with mock.patch.object(
            self.compositor, "wait", side_effect=lambda _: setattr(self.compositor, "pid", 124)
        ):
            with self.assertRaisesRegex(ValueError, "compositor child"):
                self.prepare()
        self.assertNotIn(("output", "remove", display.OUTPUT), self.compositor.calls)

    def test_interrupted_startup_removes_its_own_output(self):
        self.compositor.ready = False
        with mock.patch.object(self.compositor, "wait", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                self.prepare()
        self.assertEqual(self.compositor.calls[-1], ("output", "remove", display.OUTPUT))

    def test_malformed_or_duplicate_instance_inventory_fails(self):
        for inventory in ({}, [None], [{"instance": "test", "pid": 123}] * 2):
            with self.subTest(inventory=inventory), self.assertRaises(ValueError):
                display.assert_dedicated_instance(inventory, "test", 123)

    def test_timeout_must_be_finite_and_short_before_mutation(self):
        for timeout in (0, -1, 61, float("inf"), float("nan"), True):
            with self.subTest(timeout=timeout), self.assertRaises(ValueError):
                display.prepare_output(
                    self.compositor.control,
                    self.compositor.instances,
                    "test",
                    123,
                    self.preset,
                    timeout=timeout,
                )
        self.assertEqual(self.compositor.calls, [])

    def test_mode_check_rejects_wrong_size_rate_scale_or_disabled_output(self):
        self.prepare()
        for field, value in (
            ("width", 1920),
            ("height", 1080),
            ("refreshRate", 60),
            ("scale", 2),
            ("disabled", True),
        ):
            output = self.compositor.inventory[0] | {field: value}
            self.assertFalse(display.validate_monitors([output], self.preset, ready=True))

    def test_rejects_unknown_mode_values_and_command_injection(self):
        for field, value in (
            ("width", "2560;bad"),
            ("height", -1),
            ("fps", True),
            ("fps", 1000),
            ("width", 2559),
        ):
            with self.assertRaises(ValueError):
                display.render_config(self.preset | {field: value})


if __name__ == "__main__":
    unittest.main()
