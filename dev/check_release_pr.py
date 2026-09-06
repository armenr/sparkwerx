"""Validate the release bot's explicit CI dispatch using GitHub API metadata."""

import json
import os
import sys

from quality import TITLE


def validate(pr: dict, sha: str, repo: str, ref: str) -> bool:
    return (
        pr.get("head") == sha
        and pr.get("repo") == repo
        and pr.get("base") == "main"
        and pr.get("branch") == "release-please--branches--main"
        and ref == "refs/heads/release-please--branches--main"
        and pr.get("state") == "open"
        and TITLE.fullmatch(pr.get("title", "")) is not None
    )


if __name__ == "__main__":
    if not validate(
        json.load(sys.stdin),
        os.environ["GITHUB_SHA"],
        os.environ["GITHUB_REPOSITORY"],
        os.environ["GITHUB_REF"],
    ):
        raise SystemExit("Release CI dispatch does not match the open release PR")
