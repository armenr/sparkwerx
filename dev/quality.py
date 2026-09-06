#!/usr/bin/env python3
"""Shared development checks; never activate profiles or operate host services."""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "dev/legacy-checks.json"
TITLE = re.compile(
    r"(?:feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(?:\([^()\r\n]+\))?!?: \S[^\r\n]*"
)


def run(args: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=ROOT, text=True, check=False, **kwargs)


def files() -> list[Path]:
    names = (
        subprocess.check_output(
            ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT
        )
        .decode()
        .split("\0")
    )
    return sorted({ROOT / name for name in names if name and (ROOT / name).is_file()})


def kind(path: Path) -> str:
    if path.suffix in {".py", ".nix", ".json"}:
        return path.suffix[1:]
    if path.suffix == ".sh" or path.read_bytes().split(b"\n", 1)[0] in {
        b"#!/usr/bin/env bash",
        b"#!/bin/bash",
        b"#!/bin/sh",
        b"#!/usr/bin/env sh",
    }:
        return "sh"
    return ""


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def commands(path: Path) -> dict[str, list[str]]:
    name = str(path.relative_to(ROOT))
    return {
        "sh": {
            "shellcheck": ["shellcheck", "--external-sources", "--format=gcc", name],
            "shfmt": ["shfmt", "-d", "-i", "2", "-ci", name],
        },
        "nix": {"nixfmt": ["nixfmt", "--check", name]},
        "py": {
            "ruff": ["ruff", "check", "--config", "dev/ruff.toml", name],
            "ruff-format": ["ruff", "format", "--check", "--config", "dev/ruff.toml", name],
        },
    }.get(kind(path), {})


def syntax(path: Path) -> None:
    match kind(path):
        case "py":
            ast.parse(path.read_text(), filename=str(path), feature_version=(3, 12))
        case "json":
            json.loads(path.read_text())
        case "sh":
            result = run(["bash", "-n", str(path)], capture_output=True)
            if result.returncode:
                raise ValueError(result.stderr.strip())


def lint() -> int:
    baseline = json.loads(BASELINE.read_text())
    errors = 0
    legacy = 0
    for path in files():
        name = str(path.relative_to(ROOT))
        try:
            syntax(path)
        except (SyntaxError, ValueError) as error:
            print(f"FAIL|syntax|{name}: {error}", file=sys.stderr)
            errors += 1
        for tool, command in commands(path).items():
            result = run(command, capture_output=True)
            if not result.returncode:
                continue
            accepted = baseline.get(name, {})
            if accepted.get("sha256") == digest(path) and tool in accepted.get("checks", []):
                legacy += 1
            else:
                print(result.stdout + result.stderr, file=sys.stderr)
                errors += 1
    for command in (
        ["python3", "scripts/check-docs.py", "--self-test"],
        ["actionlint", "-color"],
        ["pre-commit", "validate-config"],
    ):
        errors += bool(run(command).returncode)
    title = os.environ.get("PR_TITLE", "")
    if title and not TITLE.fullmatch(title):
        print(
            "FAIL|pr_title|use a Conventional Commit title, e.g. fix: preserve SSH access",
            file=sys.stderr,
        )
        errors += 1
    version = (ROOT / "version.txt").read_text().strip()
    manifest = json.loads((ROOT / ".release-please-manifest.json").read_text())
    if manifest != {".": version} or not re.fullmatch(r"\d+\.\d+\.\d+(?:-[\w.]+)?", version):
        print("FAIL|release|version.txt and the release manifest must agree", file=sys.stderr)
        errors += 1
    print(
        f"INFO|legacy_checks|{legacy} accepted checks on unchanged historical files; see dev/legacy-checks.json"
    )
    return int(bool(errors))


def format_paths(names: list[str]) -> int:
    if not names:
        raise ValueError("name the files to format; there is no repository-wide rewrite command")
    available = set(files())
    # Validate the entire request before allowing the first write.
    paths = [Path(name).resolve() for name in names]
    if any(path not in available or not path.is_relative_to(ROOT) for path in paths):
        raise ValueError("format accepts only named, non-ignored files in this checkout")
    for path in paths:
        name = str(path.relative_to(ROOT))
        command = {
            "sh": ["shfmt", "-w", "-i", "2", "-ci", name],
            "nix": ["nixfmt", name],
            "py": ["ruff", "format", "--config", "dev/ruff.toml", name],
        }.get(kind(path))
        if command is None:
            raise ValueError(f"no formatter configured for {name}")
        if run(command).returncode:
            return 1
    return 0


def hooks(uninstall: bool = False) -> int:
    if uninstall:
        return run(["pre-commit", "uninstall"]).returncode
    custom = run(["git", "config", "--get", "core.hooksPath"], capture_output=True)
    if custom.returncode == 0:
        raise ValueError(
            "core.hooksPath is already configured; preserve it and resolve hook ownership first"
        )
    hook = (
        ROOT
        / subprocess.check_output(["git", "rev-parse", "--git-path", "hooks/pre-commit"], cwd=ROOT)
        .decode()
        .strip()
    )
    if hook.exists() and "File generated by pre-commit:" not in hook.read_text():
        raise ValueError(
            "an existing pre-commit hook belongs to another tool; refusing to replace it"
        )
    return run(["pre-commit", "install"]).returncode


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["lint", "check", "format", "hooks", "unhook"])
    parser.add_argument("paths", nargs="*")
    args = parser.parse_args()
    if args.command == "format":
        return format_paths(args.paths)
    if args.command in {"hooks", "unhook"}:
        return hooks(uninstall=args.command == "unhook")
    if lint():
        return 1
    if args.command == "check":
        for command in (
            ["python3", "-m", "unittest", "discover", "-s", "dev", "-p", "test_*.py"],
            ["./scripts/test-systemd-snapshot-property.sh"],
            ["./scripts/check.sh", "--no-write-lock-file"],
        ):
            if run(command).returncode:
                return 1
    print(f"PASS|dev|{args.command}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError) as error:
        print(f"FAIL|dev|{error}", file=sys.stderr)
        raise SystemExit(1) from error
