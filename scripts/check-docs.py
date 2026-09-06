#!/usr/bin/env python3
"""Check repository documentation locally without fetching links or running examples."""

from __future__ import annotations

import argparse
import html
import json
import re
import subprocess
import sys
import unicodedata
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parent.parent
PROSE_SUFFIXES = {".md", ".rst", ".txt", ".adoc", ".yaml", ".yml", ".svg"}
# The owner's writing preference applies to all published documentation,
# including historical prose. Report locations without echoing the wording.
RETIRED_WORD = re.compile(r"\bb" + r"ounded\b", re.IGNORECASE)
FENCES = re.compile(
    r"^[ \t]*(?P<mark>`{3,}|~{3,})(?P<lang>[\w-]*)[^\n]*\n"
    r"(?P<body>.*?)^[ \t]*(?P=mark)[ \t]*$",
    re.MULTILINE | re.DOTALL,
)
LINKS = re.compile(r"!?\[[^\]]*\]\(\s*(<[^>]+>|[^\s)]+)(?:\s+[^)]*)?\)")
HTML_LINKS = re.compile(r"\b(?:href|src)=[\"']([^\"']+)[\"']", re.IGNORECASE)
ACTIVE_GUIDES = {
    "README.md", "AGENTS.md", "docs/README.md", "docs/status.md",
    "docs/getting-started.md", "docs/configuration.md", "docs/architecture.md",
    "docs/operations.md", "docs/agent-guide.md", "docs/desktop-modes.md",
    ".agents/skills/dgx-spark-ops/SKILL.md",
    ".agents/skills/dgx-spark-ops/references/prompt-library.md",
}


def prose(text: str) -> str:
    """Hide code fences while preserving line numbers for useful diagnostics."""
    return FENCES.sub(lambda match: "\n" * match.group().count("\n"), text)


def anchors(text: str) -> set[str]:
    result: set[str] = set()
    counts: dict[str, int] = {}
    for heading in re.findall(r"^#{1,6}\s+(.+?)\s*#*\s*$", prose(text), re.MULTILINE):
        heading = re.sub(r"\[([^]]+)\]\([^)]+\)", r"\1", heading)
        heading = html.unescape(re.sub(r"<[^>]*>", "", heading)).lower()
        slug = "".join(
            ch for ch in heading
            if ch in "-_ " or unicodedata.category(ch)[0] in {"L", "N", "M"}
        ).replace(" ", "-")
        count = counts.get(slug, 0)
        counts[slug] = count + 1
        result.add(f"{slug}-{count}" if count else slug)
    result.update(re.findall(r"\b(?:id|name)=[\"']([^\"']+)[\"']", prose(text)))
    return result


def links(text: str) -> list[tuple[int, str]]:
    clean = prose(text)
    return [
        (clean.count("\n", 0, match.start()) + 1, html.unescape(match[1].strip("<>")))
        for pattern in (LINKS, HTML_LINKS)
        for match in pattern.finditer(clean)
    ]


def tracked_and_new_files() -> set[Path]:
    names = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT
    ).decode().split("\0")
    return {ROOT / name for name in names if name and (ROOT / name).is_file()}


def check() -> int:
    files = tracked_and_new_files()
    documents = sorted(p for p in files if p.suffix.lower() in PROSE_SUFFIXES)
    errors: list[str] = []
    link_count = 0
    example_count = 0

    for path in documents:
        relative = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding="utf-8")
        for match in RETIRED_WORD.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            errors.append(f"{relative}:{line}: replace retired wording")
        if path.suffix == ".svg":
            try:
                ET.fromstring(text)
            except ET.ParseError as error:
                errors.append(f"{relative}: invalid SVG: {error}")
        if path.suffix != ".md":
            continue

        for line, target in links(text):
            parsed = urlsplit(target)
            if parsed.scheme or parsed.netloc:
                continue  # External URL availability is deliberately not checked.
            link_count += 1
            destination = (path.parent / unquote(parsed.path)).resolve() if parsed.path else path
            prefix = f"{relative}:{line}"
            if not destination.is_relative_to(ROOT):
                errors.append(f"{prefix}: local link escapes the repository: {target}")
            elif not destination.exists():
                errors.append(f"{prefix}: missing local link: {target}")
            elif destination.is_file() and destination not in files:
                errors.append(f"{prefix}: link points to ignored/unpublished material: {target}")
            elif destination.is_dir() and not any(destination in p.parents for p in files):
                errors.append(f"{prefix}: linked directory has no published files: {target}")
            elif parsed.fragment and destination.suffix == ".md":
                if unquote(parsed.fragment) not in anchors(destination.read_text(encoding="utf-8")):
                    errors.append(f"{prefix}: missing local heading: {target}")

        if relative not in ACTIVE_GUIDES:
            continue  # Historical transcripts need not be runnable shell snippets.
        for block in FENCES.finditer(text):
            language, body = block["lang"], block["body"]
            line = text.count("\n", 0, block.start()) + 1
            if language in {"bash", "sh", "shell"}:
                example_count += 1
                result = subprocess.run(
                    ["bash", "-n"], input=body, text=True, capture_output=True, check=False
                )
                if result.returncode:
                    errors.append(f"{relative}:{line}: shell syntax: {result.stderr.strip()}")
            elif language == "json":
                example_count += 1
                try:
                    json.loads(body)
                except json.JSONDecodeError as error:
                    errors.append(f"{relative}:{line}: JSON syntax: {error}")

    for error in errors:
        print(f"FAIL|docs|{error}", file=sys.stderr)
    if errors:
        return 1
    print(
        f"PASS|docs|{len(documents)} documents; {link_count} local links; "
        f"{example_count} shell/JSON examples; wording and SVG checks passed"
    )
    print("INFO|docs|no external links fetched and no example commands executed")
    return 0


def self_test() -> None:
    sample = "# Hello, `World`!\n\n## Same\n\n## Same\n\n```text\n# Hidden\n[x](missing)\n```\n"
    assert anchors(sample) == {"hello-world", "same", "same-1"}
    assert links(sample) == []
    assert links('[x](../README.md#hello)\n<img src="assets/a.svg">') == [
        (1, "../README.md#hello"), (2, "assets/a.svg")
    ]
    assert links('[multi\nline](../README.md)') == [(1, "../README.md")]
    assert anchors('# [A link](page.md)\n<a id="custom"></a>\n') == {"a-link", "custom"}
    assert RETIRED_WORD.search("B" + "OUNDED")
    assert not RETIRED_WORD.search("explicit scope and a ten-minute timeout")
    assert subprocess.run(["bash", "-n"], input="echo ok\n", text=True, capture_output=True).returncode == 0
    assert subprocess.run(["bash", "-n"], input="if then\n", text=True, capture_output=True).returncode != 0
    print("PASS|docs_self_test|links, fences, anchors, wording, and shell-syntax checks passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="also exercise the checker before scanning")
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
    raise SystemExit(check())
