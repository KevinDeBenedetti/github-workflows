#!/usr/bin/env python3
"""Put a generated description into the managed block of a pull request body.

    merge-body.py CURRENT_BODY DESCRIPTION OUTPUT

The managed block sits between two HTML comments, invisible on GitHub:

    <!-- pr-description:start (rewritten on every push: ...) -->
    generated description
    <!-- pr-description:end -->

An existing block is replaced in place; everything outside it (your own notes,
a pull request template, "Closes #12") is kept byte for byte. Without a block,
one goes on top of the existing body.

Exit status: 0 written, 1 unusable description or body too long, 2 usage.
"""
from __future__ import annotations

import re
import sys

START = "<!-- pr-description:start (rewritten on every push: write your own notes outside this block) -->"
END = "<!-- pr-description:end -->"
# Any start marker, whatever its comment text, up to the first end marker.
BLOCK = re.compile(r"<!--\s*pr-description:start\b.*?-->.*?<!--\s*pr-description:end\s*-->", re.S)
MARKER = re.compile(r"<!--\s*pr-description:(?:start|end)\b.*?-->", re.S)
# A model sometimes wraps its whole answer in a code fence.
FENCE = re.compile(r"\A```[\w-]*[ \t]*\r?\n(?P<inner>.*?)\r?\n```\s*\Z", re.S)
MAX_DESCRIPTION = 20_000  # characters: nobody reads a longer description
BODY_LIMIT = 65_536  # GitHub rejects a longer pull request body


def read(path: str) -> str:
    # newline="": keep CRLF as is, so an unchanged body stays byte-identical.
    with open(path, encoding="utf-8", newline="") as f:
        return f.read()


def write(path: str, text: str) -> None:
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)


def clean(text: str) -> str:
    text = text.strip()
    fenced = FENCE.match(text)
    if fenced:
        text = fenced.group("inner").strip()
    # The description must not open or close the block by itself.
    text = MARKER.sub("", text).strip()
    if len(text) > MAX_DESCRIPTION:
        cut = text.rfind("\n", 0, MAX_DESCRIPTION)
        text = text[: cut if cut > 0 else MAX_DESCRIPTION].rstrip() + "\n\n_(description truncated)_"
    return text


def merge(current: str, description: str) -> str:
    block = f"{START}\n{description}\n{END}"
    if BLOCK.search(current):
        return BLOCK.sub(lambda _: block, current, count=1)
    if current.strip():
        return f"{block}\n\n{current}"
    return block


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    current = read(argv[0])
    description = clean(read(argv[1]))
    if not description:
        print("error: the generated description is empty", file=sys.stderr)
        return 1
    body = merge(current, description)
    if len(body) > BODY_LIMIT:
        print(
            f"error: the body would be {len(body)} characters long, over GitHub's limit of {BODY_LIMIT}",
            file=sys.stderr,
        )
        return 1
    write(argv[2], body)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
