"""Guided package changes: real Git, isolated files, controlled build failures."""

import contextlib
import io
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from test_workstation import ws


class GuidedTests(unittest.TestCase):
    def setUp(self):
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.root = Path(self.stack.enter_context(tempfile.TemporaryDirectory()))
        self.home = self.root / "home"
        self.home.mkdir()
        self.repo = self.root / "repo"
        self.repo.mkdir()
        (self.repo / "workstations").mkdir()
        self.hosts = self.repo / "workstations/hosts.json"
        # Operator tests must not change meaning when the real owner installs btop.
        self.hosts.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "hosts": {
                        "spark-9667": {
                            "system": "aarch64-linux",
                            "desktop": "factory-gnome",
                            "user": "deadspark",
                            "uid": 1000,
                            "homeDirectory": "/home/deadspark",
                            "packages": [
                                "nh",
                                "nix-output-monitor",
                                "nix-search-tv",
                                "fzf",
                                "networkmanager",
                            ],
                        }
                    },
                }
            )
        )
        self.original = self.hosts.read_bytes()
        self.pin = {
            "nodes": {
                "root": {"inputs": {"nixpkgs-workstation": "packages"}},
                "packages": {"locked": {"rev": "original-revision"}},
            }
        }
        self.lock_bytes = json.dumps(self.pin).encode()
        (self.repo / "flake.lock").write_bytes(self.lock_bytes)
        self.real_run = ws.run
        self.stack.enter_context(patch.object(ws, "ROOT", self.repo))
        self.stack.enter_context(patch.object(ws, "HOSTS", self.hosts))
        self.stack.enter_context(patch.object(ws.Path, "home", return_value=self.home))
        self.stack.enter_context(patch.object(ws, "require_target"))
        self.stack.enter_context(patch("sys.stdout", new_callable=io.StringIO))
        self.real_run(["git", "init", "-q"])
        self.real_run(["git", "add", "."])
        self.real_run(
            [
                "git",
                "-c",
                "user.name=Test",
                "-c",
                "user.email=test@localhost",
                "commit",
                "-qm",
                "fixture",
            ]
        )
        self.candidate = self.root / "output"
        self.candidate.mkdir()
        (self.candidate / "workstation.json").write_text(
            json.dumps({"packages": [{"name": "btop", "version": "1.4.7"}]})
        )
        self.stack.enter_context(
            patch.object(ws, "validated_candidate", return_value=str(self.candidate))
        )
        self.apply = self.stack.enter_context(patch.object(ws.Profile, "apply"))
        self.after_build = lambda: None

        def run(args, *, capture=False):
            if args[0] != "nix":
                return self.real_run(args, capture=capture)
            if "build" in args:
                Path(args[args.index("--out-link") + 1]).symlink_to(self.candidate)
                self.after_build()
            elif "eval" in args:
                return str(self.candidate)
            elif "update" in args:
                self.pin["nodes"]["packages"]["locked"]["rev"] = "updated-revision"
                (self.repo / "flake.lock").write_text(json.dumps(self.pin))
            return ""

        self.stack.enter_context(patch.object(ws, "run", side_effect=run))

    def clean(self):
        self.assertEqual(self.real_run(["git", "status", "--porcelain"], capture=True), "")
        self.assertEqual(list(ws.Profile(self.home).state.glob("preview-*")), [])

    def test_cancel_restores_selection_without_activating(self):
        with patch("builtins.input", return_value="n"):
            ws.guided_change("install", "spark-9667", ["btop"])
        self.assertEqual(self.hosts.read_bytes(), self.original)
        self.apply.assert_not_called()
        self.clean()

    def test_failed_build_restores_files_and_cleans_preview(self):
        def fail():
            raise subprocess.CalledProcessError(1, "build")

        self.after_build = fail
        with self.assertRaises(subprocess.CalledProcessError):
            ws.guided_change("install", "spark-9667", ["btop"])
        self.assertEqual(self.hosts.read_bytes(), self.original)
        self.apply.assert_not_called()
        self.clean()

    def test_interruption_during_confirmation_restores_files(self):
        with (
            patch("builtins.input", side_effect=KeyboardInterrupt),
            self.assertRaises(KeyboardInterrupt),
        ):
            ws.guided_change("install", "spark-9667", ["btop"])
        self.assertEqual(self.hosts.read_bytes(), self.original)
        self.apply.assert_not_called()
        self.clean()

    def test_success_commits_before_activation(self):
        def verify(candidate):
            self.assertEqual(candidate, str(self.candidate))
            self.assertIn(
                "btop",
                json.loads(
                    self.real_run(["git", "show", "HEAD:workstations/hosts.json"], capture=True)
                )["hosts"]["spark-9667"]["packages"],
            )

        self.apply.side_effect = verify
        with patch("builtins.input", return_value="yes"):
            ws.guided_change("install", "spark-9667", ["btop"])
        self.apply.assert_called_once()
        self.clean()

    def test_activation_failure_keeps_committed_selection(self):
        self.apply.side_effect = ValueError("postflight failed")
        with (
            patch("builtins.input", return_value="y"),
            self.assertRaisesRegex(ValueError, "postflight"),
        ):
            ws.guided_change("install", "spark-9667", ["btop"])
        self.assertIn("btop", ws.declaration("spark-9667")["packages"])
        self.clean()

    def test_cancel_upgrade_restores_original_pin(self):
        with patch("builtins.input", return_value="n"):
            ws.guided_change("upgrade", "spark-9667")
        self.assertEqual((self.repo / "flake.lock").read_bytes(), self.lock_bytes)
        self.apply.assert_not_called()
        self.clean()

    def test_existing_edits_are_refused(self):
        self.hosts.write_bytes(self.original + b"\n")
        with self.assertRaisesRegex(ValueError, "Unsaved"):
            ws.guided_change("install", "spark-9667", ["btop"])
        self.assertEqual(self.hosts.read_bytes(), self.original + b"\n")
        self.apply.assert_not_called()

    def pending_selection(self):
        data = json.loads(self.original)
        data["hosts"]["spark-9667"]["packages"].append("btop")
        ws.write_json(self.hosts, data)
        return self.hosts.read_bytes()

    def test_finish_commits_existing_selection_before_activation(self):
        selected = self.pending_selection()

        def verify(candidate):
            self.assertEqual(candidate, str(self.candidate))
            self.assertEqual(
                self.real_run(["git", "show", "HEAD:workstations/hosts.json"], capture=True),
                selected.decode(),
            )
            self.assertEqual(self.real_run(["git", "status", "--porcelain"], capture=True), "")

        self.apply.side_effect = verify
        with patch("builtins.input", return_value="y"):
            ws.execute("finish", "spark-9667")
        self.apply.assert_called_once()
        self.clean()

    def test_finish_cancellation_preserves_preexisting_edits(self):
        selected = self.pending_selection()
        with patch("builtins.input", return_value="n"):
            ws.execute("finish", "spark-9667")
        self.assertEqual(self.hosts.read_bytes(), selected)
        self.apply.assert_not_called()

    def test_finish_build_failure_preserves_preexisting_edits(self):
        selected = self.pending_selection()

        def fail():
            raise subprocess.CalledProcessError(1, "build")

        self.after_build = fail
        with self.assertRaises(subprocess.CalledProcessError):
            ws.execute("finish", "spark-9667")
        self.assertEqual(self.hosts.read_bytes(), selected)
        self.apply.assert_not_called()

    def test_finish_interruption_preserves_preexisting_edits(self):
        selected = self.pending_selection()
        with patch("builtins.input", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                ws.execute("finish", "spark-9667")
        self.assertEqual(self.hosts.read_bytes(), selected)
        self.apply.assert_not_called()

    def test_finish_rejects_untracked_workload_without_staging_it(self):
        selected = self.pending_selection()
        workload = self.repo / "compose.yaml"
        workload.write_text("services: {}\n")
        with self.assertRaisesRegex(ValueError, "compose.yaml"):
            ws.execute("finish", "spark-9667")
        self.assertEqual(self.hosts.read_bytes(), selected)
        self.assertEqual(workload.read_text(), "services: {}\n")
        self.assertEqual(self.real_run(["git", "diff", "--cached"], capture=True), "")
        self.apply.assert_not_called()

    def test_blocker_is_reported_before_search(self):
        self.pending_selection()
        with patch.object(ws, "catalog") as catalog:
            with self.assertRaisesRegex(ValueError, "spark finish"):
                ws.execute("install", "spark-9667", "btop-cuda")
        catalog.assert_not_called()

    def test_setup_rejects_pending_edits_before_bootstrap(self):
        selected = self.pending_selection()
        with patch.object(ws, "run", wraps=self.real_run) as command:
            with self.assertRaisesRegex(ValueError, "spark finish"):
                ws.execute("setup", "spark-9667")
        self.assertTrue(all(call.args[0][0] == "git" for call in command.call_args_list))
        self.assertEqual(self.hosts.read_bytes(), selected)

    def test_finish_preserves_intervening_edits(self):
        self.pending_selection()
        intervening = self.original + b"\n\n"
        self.after_build = lambda: self.hosts.write_bytes(intervening)
        with patch("builtins.input", return_value="y"):
            with self.assertRaisesRegex(ValueError, "changed during"):
                ws.execute("finish", "spark-9667")
        self.assertEqual(self.hosts.read_bytes(), intervening)
        self.apply.assert_not_called()

    def test_finish_rejects_candidate_mismatch_after_save(self):
        self.pending_selection()
        with (
            patch("builtins.input", return_value="y"),
            patch.object(ws, "expected_candidate", return_value="/different-output"),
        ):
            with self.assertRaisesRegex(ValueError, "Candidate differs"):
                ws.execute("finish", "spark-9667")
        self.apply.assert_not_called()
        self.clean()

    def test_plan_labels_stale_candidate_without_showing_old_packages(self):
        self.pending_selection()
        profile = ws.Profile(self.home)
        profile.prepare()
        profile.candidate.symlink_to(self.candidate)
        output = io.StringIO()
        with (
            patch.object(ws, "show_status"),
            patch.object(ws, "expected_candidate", return_value="/different-output"),
            patch("sys.stdout", output),
        ):
            ws.execute("plan", "spark-9667")
        self.assertIn("STALE", output.getvalue())
        self.assertNotIn("1.4.7", output.getvalue())
        self.assertIn("spark finish", output.getvalue())

    def test_uninstall_commits_selection_and_activates(self):
        with patch("builtins.input", return_value="y"):
            ws.guided_change("uninstall", "spark-9667", ["nix-search-tv"])
        self.assertNotIn("nix-search-tv", ws.declaration("spark-9667")["packages"])
        self.apply.assert_called_once()
        self.clean()

    def test_upgrade_commits_new_pin_before_activation(self):
        with patch("builtins.input", return_value="y"):
            ws.guided_change("upgrade", "spark-9667")
        committed = json.loads(self.real_run(["git", "show", "HEAD:flake.lock"], capture=True))
        self.assertEqual(committed["nodes"]["packages"]["locked"]["rev"], "updated-revision")
        self.apply.assert_called_once()
        self.clean()

    def test_existing_selection_is_a_noop_without_reformatting(self):
        with patch("builtins.input") as confirm:
            ws.guided_change("install", "spark-9667", ["nh"])
        confirm.assert_not_called()
        self.apply.assert_not_called()
        self.assertEqual(self.hosts.read_bytes(), self.original)
        self.clean()

    def test_intervening_edits_are_preserved_and_not_activated(self):
        self.after_build = lambda: self.hosts.write_bytes(self.original + b"\n")
        with (
            patch("builtins.input", return_value="y"),
            self.assertRaisesRegex(ValueError, "changed during"),
        ):
            ws.guided_change("install", "spark-9667", ["btop"])
        self.assertEqual(self.hosts.read_bytes(), self.original + b"\n")
        self.apply.assert_not_called()


class PickerTests(unittest.TestCase):
    def test_catalog_uses_platform_list_not_index_system_and_prioritizes_exact_match(self):
        records = [
            {
                "package_attr_name": attr,
                "package_platforms": platforms,
                "package_system": "x86_64-linux",
            }
            for attr, platforms in [
                ("btop-cuda", ["aarch64-linux"]),
                ("btop", ["aarch64-linux"]),
                ("other", ["x86_64-linux"]),
                ("bad\tname", ["aarch64-linux"]),
            ]
        ]
        with patch.object(ws, "run", return_value=json.dumps({"results": records})):
            self.assertEqual(
                [p["package_attr_name"] for p in ws.catalog("btop", "aarch64-linux")],
                ["btop", "btop-cuda"],
            )

    def test_cancel_returns_no_selection_and_controls_are_removed(self):
        with (
            patch.object(ws.shutil, "which", return_value="/bin/fzf"),
            patch.object(
                ws.subprocess, "run", return_value=subprocess.CompletedProcess([], 130, "")
            ) as command,
        ):
            self.assertEqual(ws.pick([("btop", "btop\n\x1bcontrol")], "Packages"), [])
        self.assertEqual(command.call_args.kwargs["input"], "btop\tbtop  control\n")
        self.assertEqual(command.call_args.kwargs["env"]["FZF_DEFAULT_OPTS"], "")

    def test_picker_rejects_unoffered_attributes(self):
        with (
            patch.object(ws.shutil, "which", return_value="/bin/fzf"),
            patch.object(
                ws.subprocess,
                "run",
                return_value=subprocess.CompletedProcess([], 0, "unoffered\tname\n"),
            ),
            self.assertRaisesRegex(ValueError, "unknown selection"),
        ):
            ws.pick([("btop", "btop")], "Packages")
