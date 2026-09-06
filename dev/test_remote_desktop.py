"""Selection/privacy regression tests; no desktop, network, or sudo operations."""

import copy
import importlib.machinery
import importlib.util
import json
import os
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
loader = importlib.machinery.SourceFileLoader(
    "remote_desktop", str(ROOT / "scripts/dgx-remote-desktop")
)
spec = importlib.util.spec_from_loader(loader.name, loader)
remote = importlib.util.module_from_spec(spec)
loader.exec_module(remote)
network_spec = importlib.util.spec_from_file_location(
    "remote_network_test", ROOT / "remote-desktop/network-test.py"
)
network = importlib.util.module_from_spec(network_spec)
network_spec.loader.exec_module(network)


class RemoteDesktopTests(unittest.TestCase):
    def setUp(self):
        self.hosts = json.loads((ROOT / "fleet/hosts.json").read_text())["hosts"]
        self.host = copy.deepcopy(self.hosts["sparkle-01"])
        self.defaults = json.loads((ROOT / "remote-desktop/defaults.json").read_text())
        self.presets = json.loads((ROOT / "remote-desktop/client-presets.json").read_text())

    def plan(self):
        return remote.plan(self.host, self.defaults, self.presets)

    def test_default_off(self):
        self.host["desktop"].pop("remoteDesktop", None)
        self.assertEqual(self.plan()["state"], "DISABLED")

    def test_selected_headless_is_dormant(self):
        self.assertEqual(self.plan()["state"], "DORMANT_HEADLESS")

    def test_graphical_selection_is_not_activation(self):
        for mode in ("gnome", "hyprland", "kde"):
            self.host["desktop"]["mode"] = mode
            self.assertEqual(self.plan()["state"], "PREPARATION_REQUIRED")

    def test_tailscale_required_only_when_selected(self):
        self.host["access"]["tailscale"]["selected"] = False
        with self.assertRaisesRegex(ValueError, "requires.*Tailscale"):
            self.plan()
        self.host["desktop"]["remoteDesktop"]["selected"] = False
        self.assertEqual(self.plan()["state"], "DISABLED")

    def test_no_alternate_transport_or_unknown_enable_switch(self):
        for field, value in (("transport", "lan"), ("backend", "rdp"), ("enabled", True)):
            with self.subTest(field=field):
                self.host["desktop"]["remoteDesktop"] = self.defaults | {
                    "selected": True,
                    field: value,
                }
                with self.assertRaises(ValueError):
                    self.plan()

    def test_strict_types_and_presets(self):
        for field, value in (
            ("selected", "false"),
            ("selected", 1),
            ("clientPreset", []),
            ("clientPreset", "8k240"),
        ):
            with self.subTest(field=field, value=value):
                self.host["desktop"]["remoteDesktop"] = self.defaults | {field: value}
                with self.assertRaises(ValueError):
                    self.plan()

    def test_no_secret_or_address_configuration(self):
        for field in ("password", "bind_address", "credentials_file", "authKey"):
            self.host["desktop"]["remoteDesktop"] = self.defaults | {field: "do-not-store"}
            with self.assertRaises(ValueError):
                self.plan()

    def test_plan_is_pure(self):
        before = copy.deepcopy(self.host)
        with mock.patch.object(
            remote.subprocess, "run", side_effect=AssertionError("not read-only")
        ):
            self.plan()
        self.assertEqual(before, self.host)

    def test_network_test_refuses_host_namespace_before_any_command(self):
        with (
            mock.patch.object(network.os, "geteuid", return_value=0),
            mock.patch.object(network.os, "readlink", return_value="net:[same-namespace]"),
            mock.patch.object(network, "command") as command,
        ):
            with self.assertRaisesRegex(RuntimeError, "private network namespace"):
                network.run_test("not-read")
            command.assert_not_called()

    def test_nix_and_python_plans_agree(self):
        path = os.environ.get("DGX_REMOTE_NIX_PLANS")
        if not path:
            self.skipTest("Nix parity runs in the remote-desktop-policy check")
        for host, nix_plan in json.loads(Path(path).read_text()).items():
            result = remote.plan(self.hosts[host], self.defaults, self.presets)
            self.assertEqual(result, {key: nix_plan[key] for key in result})
            self.assertEqual(nix_plan["installedPackages"], [])
            self.assertFalse(nix_plan["activationSupported"])


if __name__ == "__main__":
    unittest.main()
