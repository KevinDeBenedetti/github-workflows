#!/usr/bin/env python3
"""Split Claude's answer into a pull request title and its description.

    split-title.py ANSWER DESCRIPTION TITLE

With the title prompt, Claude answers `Title: <header>`, an empty line, then
the description. The title is a Conventional Commit header that becomes the
squash commit and drives release-please, so it is checked before it is kept:
a known type, an optional lowercase scope, an optional `!`, a summary, at most
100 characters, and nothing that GitHub turns into a mention, a reference or a
link. A title that fails the check is not written (TITLE stays absent) and a
warning says why: the description is still used, and the pull request keeps
its title.

The answer is model output written from untrusted repository content, so the
title is data too: control, zero-width and bidirectional characters fail the
check rather than being stripped, since a title is short enough to rewrite.

Exit status: 0 written (with or without a title), 1 empty description, 2 usage.
"""
from __future__ import annotations

import re
import sys

TYPES = "feat|fix|perf|revert|docs|style|chore|test|build|ci|deps"
HEADER = re.compile(rf"(?:{TYPES})(?:\([a-z0-9][a-z0-9._/-]*\))?!?: \S(?:.*\S)?")
MAX_TITLE = 100
LINE = re.compile(r"\A\s*Title:[ \t]*(?P<title>[^\r\n]*)\r?\n", re.I)
# What GitHub links in a title, or what has no place in a commit header.
UNSAFE = re.compile(
    r"[@<>`]|#\d|\bGH-\d|://|www\."
    r"|[\x00-\x1f\x7f-\x9f​-‏ -‮⁠-⁤⁦-⁩﻿]"
)


def check(title: str) -> str | None:
    """Why ``title`` can't be used, or None when it can."""
    if not title:
        return "it is empty"
    if len(title) > MAX_TITLE:
        return f"it is {len(title)} characters long, over {MAX_TITLE}"
    if UNSAFE.search(title):
        return "it holds a mention, a reference, a URL, markup or a hidden character"
    if not HEADER.fullmatch(title):
        return "it is not a Conventional Commit header"
    if title.endswith("."):
        return "it ends with a period"
    return None


def warn(message: str) -> None:
    # Stripped of '::' so model text cannot inject a workflow command.
    print(f"::warning::{message.replace('::', ': :')}")


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2
    answer_path, description_path, title_path = argv[1:]
    with open(answer_path, encoding="utf-8") as f:
        answer = f.read()

    match = LINE.match(answer)
    if match is None:
        warn("Claude wrote no 'Title:' line: the pull request keeps its title.")
        description = answer
    else:
        title = match["title"].strip()
        description = answer[match.end() :]
        reason = check(title)
        if reason is None:
            with open(title_path, "w", encoding="utf-8") as f:
                f.write(title)
        else:
            shown = UNSAFE.sub("?", title)[:120]
            warn(f"Title not used ({reason}): {shown}")

    if not description.strip():
        print("::error::Claude Code returned an empty description.")
        return 1
    with open(description_path, "w", encoding="utf-8") as f:
        f.write(description.lstrip("\r\n"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
