"""Failure and recovery tests for the isolated workstation profile."""

import importlib.machinery
import importlib.util
import io
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
LOADER = importlib.machinery.SourceFileLoader("workstation", str(ROOT / "scripts/dgx-workstation"))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
ws = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(ws)


class ProfileTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name)
        self.profile = ws.Profile(self.home)
        self.profile.prepare()
        self.old = self.home / "old-output"
        self.new = self.home / "new-output"
        self.old.mkdir()
        self.new.mkdir()
        self.calls = []

    def tearDown(self):
        self.temp.cleanup()

    def switch(self, target):
        self.calls.append(target)
        generation = self.profile.state / f"profile-{len(self.calls)}-link"
        generation.symlink_to(target)
        temporary = self.profile.state / "switch-link"
        temporary.symlink_to(generation)
        temporary.replace(self.profile.profile)

    def test_failed_update_restores_old_generation_and_preserves_user_files(self):
        self.switch(str(self.old))
        shell = self.home / ".zshrc"
        shell.write_text("keep my shell\n")
        with (
            patch.object(self.profile, "switch", side_effect=self.switch),
            patch.object(self.profile, "smoke", side_effect=ValueError("bad executable")),
        ):
            with self.assertRaisesRegex(ValueError, "bad executable"):
                self.profile.apply(str(self.new))
        self.assertEqual(self.profile.current(), str(self.old))
        self.assertFalse(self.profile.pending.exists())
        self.assertEqual(shell.read_text(), "keep my shell\n")
        self.assertTrue(any(target == str(self.new) for _, target in self.profile.generations()))

    def test_failed_first_install_returns_to_no_profile(self):
        with (
            patch.object(self.profile, "switch", side_effect=self.switch),
            patch.object(self.profile, "smoke", side_effect=ValueError("broken")),
        ):
            with self.assertRaises(ValueError):
                self.profile.apply(str(self.new))
        self.assertIsNone(self.profile.current())
        self.assertFalse(self.profile.pending.exists())

    def test_interrupted_activation_is_recoverable_after_new_process(self):
        self.switch(str(self.old))
        ws.write_json(self.profile.pending, {"before": str(self.old), "candidate": str(self.new)})
        self.switch(str(self.new))
        fresh = ws.Profile(self.home)
        with self.assertRaisesRegex(ValueError, "Interrupted"):
            fresh.require_idle()
        with patch.object(fresh, "switch", side_effect=self.switch):
            fresh.recover()
        self.assertEqual(fresh.current(), str(self.old))

    def test_recovery_refuses_intervening_profile_change(self):
        ws.write_json(self.profile.pending, {"before": None, "candidate": str(self.new)})
        self.switch(str(self.old))
        with self.assertRaisesRegex(ValueError, "changed since"):
            self.profile.recover()
        self.assertEqual(self.profile.current(), str(self.old))
        self.assertTrue(self.profile.pending.exists())

    def test_success_and_repeat_are_idempotent(self):
        with (
            patch.object(self.profile, "switch", side_effect=self.switch),
            patch.object(self.profile, "smoke"),
        ):
            self.profile.apply(str(self.new))
            self.profile.apply(str(self.new))
        self.assertEqual(len(self.calls), 1)
        self.assertFalse(self.profile.pending.exists())

    def test_shell_integration_preserves_content_and_is_idempotent(self):
        shell = self.home / ".zshrc.local"
        original = "export MY_SETTING='keep this'\n"
        shell.write_text(original)
        self.profile.enable_shell()
        self.profile.enable_shell()
        self.assertEqual(shell.read_text().count("# Sparkwerx"), 1)
        self.assertTrue(shell.read_text().startswith(original))
        backups = list(self.profile.state.glob("zshrc.local.before-*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), original)
        self.assertEqual(backups[0].stat().st_mode & 0o777, 0o600)

    def test_shell_symlink_is_never_followed(self):
        other = self.home / "private"
        other.write_text("preserve\n")
        (self.home / ".zshrc.local").symlink_to(other)
        with self.assertRaisesRegex(ValueError, "symlink"):
            self.profile.enable_shell()
        self.assertEqual(other.read_text(), "preserve\n")

    def test_redirected_state_is_refused(self):
        redirected = self.home / "another-home"
        redirected.mkdir()
        (redirected / ".local").symlink_to(self.home / ".local")
        with self.assertRaisesRegex(ValueError, "symlinked"):
            ws.Profile(redirected).prepare()

    def test_concurrent_operator_is_refused(self):
        with self.profile.lock():
            with self.assertRaisesRegex(ValueError, "Another"):
                with ws.Profile(self.home).lock():
                    self.fail("Second lock was acquired")

    def test_wrong_host_is_rejected_before_nix(self):
        with (
            patch.object(ws, "run") as command,
            patch.object(ws.os, "geteuid", return_value=1000),
            patch.object(ws.platform, "node", return_value="different-host"),
        ):
            with self.assertRaises(ValueError):
                ws.execute("apply", "spark-9667")
        command.assert_not_called()

    def test_noninteractive_menu_has_clear_error(self):
        result = subprocess.run(
            [str(ROOT / "scripts/dgx-workstation"), "--host", "spark-9667"],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("menu requires a terminal", result.stderr)

    def test_workstation_does_not_select_personal_or_root_roles(self):
        data = json.loads(ws.HOSTS.read_text())
        spec = data["hosts"]["spark-9667"]
        self.assertEqual(spec["desktop"], "factory-gnome")
        self.assertEqual(spec["user"], "deadspark")
        for forbidden in ("tailscale", "codex", "workloads", "system-manager"):
            self.assertNotIn(forbidden, spec)


class SaveTests(unittest.TestCase):
    def test_save_records_only_configuration_and_refuses_other_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            (repo / "workstations").mkdir()
            selected = repo / "workstations/hosts.json"
            selected.write_text("{}\n")
            (repo / "flake.lock").write_text("{}\n")
            (repo / "keep.txt").write_text("unchanged\n")
            with patch.object(ws, "ROOT", repo):
                ws.run(["git", "init", "-q"])
                ws.run(["git", "add", "."])
                ws.run(
                    [
                        "git",
                        "-c",
                        "user.name=Test",
                        "-c",
                        "user.email=test@localhost",
                        "commit",
                        "-qm",
                        "initial fixture",
                    ]
                )
                selected.write_text('{"updated": true}\n')
                ws.execute("save", "spark-9667")
                self.assertEqual(ws.run(["git", "status", "--porcelain"], capture=True), "")
                self.assertEqual(
                    ws.run(
                        ["git", "show", "--format=", "--name-only", "HEAD"], capture=True
                    ).strip(),
                    "workstations/hosts.json",
                )
                selected.write_text("{}\n")
                (repo / "keep.txt").write_text("unrelated edit\n")
                with self.assertRaisesRegex(ValueError, "Other repository changes"):
                    ws.execute("save", "spark-9667")
                self.assertEqual(ws.run(["git", "diff", "--cached"], capture=True), "")


class SearchTests(unittest.TestCase):
    def test_installed_command_is_reported_without_nix_search_backend(self):
        output = io.StringIO()
        with (
            patch.object(
                ws.shutil, "which", side_effect=lambda name: {"nmtui": "/usr/bin/nmtui"}.get(name)
            ),
            patch.object(ws, "run") as command,
            patch("sys.stdout", output),
        ):
            ws.execute("search", "spark-9667", "nmtui")
        command.assert_not_called()
        self.assertIn("Already available on this machine: /usr/bin/nmtui", output.getvalue())
        self.assertIn("catalog search is unavailable", output.getvalue())

    def test_missing_backend_has_setup_guidance(self):
        with (
            patch.object(ws.shutil, "which", return_value=None),
            patch.object(ws, "run") as command,
        ):
            with self.assertRaisesRegex(ValueError, "pending Nix workstation setup"):
                ws.execute("search", "spark-9667", "uninstalled-example")
        command.assert_not_called()

    def test_available_backend_still_searches_catalog(self):
        with (
            patch.object(
                ws.shutil, "which", side_effect=lambda name: {"nh": "/example/bin/nh"}.get(name)
            ),
            patch.object(ws, "run") as command,
        ):
            ws.execute("search", "spark-9667", "nmtui")
        command.assert_called_once_with(["nh", "search", "--channel", "nixos-26.05", "nmtui"])

    def test_missing_nix_binary_has_setup_guidance(self):
        with patch.object(ws.subprocess, "run", side_effect=FileNotFoundError("nix")):
            with self.assertRaisesRegex(ValueError, "Nix workstation setup is incomplete"):
                ws.run(["nix", "build"])


class SetupTests(unittest.TestCase):
    def test_bootstrap_failure_stops_before_package_or_shell_changes(self):
        with (
            patch.object(ws, "require_target"),
            patch.object(ws, "require_reviewable"),
            patch.object(
                ws, "run", side_effect=subprocess.CalledProcessError(1, "bootstrap")
            ) as command,
            patch.object(ws.Profile, "lock") as profile_lock,
        ):
            with self.assertRaises(subprocess.CalledProcessError):
                ws.execute("setup", "spark-9667")
        command.assert_called_once_with(
            [str(ROOT / "workstations/bootstrap/scripts/bootstrap-nix.sh"), "spark-9667"]
        )
        profile_lock.assert_not_called()

    def test_bootstrap_adapter_reuses_unchanged_operators_and_separate_pin(self):
        adapter = ROOT / "workstations/bootstrap"
        for name in (
            "update-nix-installer.sh",
            "rollback-fresh-nix-bootstrap.sh",
        ):
            entry = adapter / "scripts" / name
            self.assertTrue(entry.is_symlink())
            self.assertEqual(entry.resolve(), ROOT / "scripts" / name)
        pilot = json.loads((ROOT / "bootstrap/nix/source.json").read_text())
        workstation = json.loads((adapter / "bootstrap/nix/source.json").read_text())
        self.assertEqual(pilot["installer"]["version"], "2.35.1")
        self.assertEqual(workstation["installer"]["version"], "2.35.2")
        self.assertEqual(pilot["linuxPlanner"], workstation["linuxPlanner"])


if __name__ == "__main__":
    unittest.main()
