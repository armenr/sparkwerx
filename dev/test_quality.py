"""Regression tests for the local checks and the release CI dispatch."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import quality
from check_release_pr import validate


class QualityTests(unittest.TestCase):
    def test_pr_titles(self):
        for title in (
            "fix: correct rollback",
            "feat(desktop)!: change mode selection",
            "chore(main): release 0.1.0",
        ):
            self.assertIsNotNone(quality.TITLE.fullmatch(title))
        for title in ("wip", "feat: ", "fix: ok\nrun something", "fix(): no scope"):
            self.assertIsNone(quality.TITLE.fullmatch(title))

    def test_release_dispatch_identity(self):
        pr = {
            "head": "abc",
            "repo": "armenr/sparkwerx",
            "base": "main",
            "branch": "release-please--branches--main--components--sparkwerx",
            "state": "open",
            "title": "chore(main): release 0.1.0",
        }
        args = (
            "abc",
            "armenr/sparkwerx",
            "refs/heads/release-please--branches--main--components--sparkwerx",
        )
        self.assertTrue(validate(pr, *args))
        for key in pr:
            self.assertFalse(validate(pr | {key: "unexpected"}, *args), key)
        self.assertFalse(validate(pr, "old-sha", args[1], args[2]))
        self.assertFalse(validate(pr, args[0], args[1], "refs/heads/main"))

    def test_reject_bad_syntax(self):
        with tempfile.TemporaryDirectory(prefix="sparkwerx-quality-") as directory:
            for filename, text in (
                ("bad.py", "if then\n"),
                ("bad.json", "{"),
                ("bad.sh", "if then\n"),
            ):
                path = Path(directory) / filename
                path.write_text(text)
                with self.assertRaises((SyntaxError, ValueError)):
                    quality.syntax(path)

    def test_format_cannot_write_outside_checkout(self):
        with tempfile.TemporaryDirectory(prefix="sparkwerx-quality-") as directory:
            path = Path(directory) / "outside.py"
            path.write_text("not_formatted=1\n")
            with self.assertRaises(ValueError):
                quality.format_paths([str(path)])
            self.assertEqual(path.read_text(), "not_formatted=1\n")

    def test_legacy_exceptions_are_exact(self):
        baseline = json.loads(quality.BASELINE.read_text())
        for name, entry in baseline.items():
            path = quality.ROOT / name
            self.assertTrue(path.is_relative_to(quality.ROOT))
            self.assertEqual(
                quality.digest(path), entry["sha256"], f"remove stale exception: {name}"
            )
            self.assertTrue(set(entry["checks"]) <= set(quality.commands(path)))

    def test_real_pre_commit_install_pass_and_fail(self):
        # Only this disposable Git repository gets a hook. No network hook repos
        # or language environments are installed; our hooks use the Nix tools.
        with tempfile.TemporaryDirectory(prefix="sparkwerx-hooks-") as directory:
            root = Path(directory)
            env = os.environ | {"PRE_COMMIT_HOME": str(root / "cache")}
            subprocess.run(["git", "init", "-q", directory], check=True)
            (root / ".pre-commit-config.yaml").write_text(
                "repos:\n- repo: local\n  hooks:\n"
                "  - id: fixture\n    name: fixture\n"
                "    entry: bash check.sh\n    language: unsupported\n"
                "    pass_filenames: false\n    always_run: true\n"
            )
            script = root / "check.sh"
            script.write_text("exit 0\n")
            subprocess.run(
                ["git", "add", ".pre-commit-config.yaml", "check.sh"], cwd=root, check=True
            )
            with patch.object(quality, "ROOT", root), patch.dict(os.environ, env):
                self.assertEqual(quality.hooks(), 0)
                # Exercise the installed hook entry, not just --version.
                self.assertEqual(
                    subprocess.run(
                        [str(root / ".git/hooks/pre-commit")], cwd=root, env=env, check=False
                    ).returncode,
                    0,
                )
                script.write_text("exit 1\n")
                subprocess.run(["git", "add", "check.sh"], cwd=root, check=True)
                self.assertNotEqual(
                    subprocess.run(
                        [str(root / ".git/hooks/pre-commit")], cwd=root, env=env, check=False
                    ).returncode,
                    0,
                )
                self.assertEqual(quality.hooks(uninstall=True), 0)
                foreign = root / ".git/hooks/pre-commit"
                foreign.write_text("#!/bin/sh\n# user hook\n")
                with self.assertRaises(ValueError):
                    quality.hooks()
                self.assertIn("user hook", foreign.read_text())


if __name__ == "__main__":
    unittest.main()
