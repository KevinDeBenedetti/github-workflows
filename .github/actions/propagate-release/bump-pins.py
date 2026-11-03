#!/usr/bin/env python3
"""Move the pins of a repository's workflows and actions to a new release.

    bump-pins.py SOURCE TAG SHA FILE...

SOURCE is owner/name, TAG the release (vX.Y.Z) and SHA its commit. In each
FILE, a reference to SOURCE/.github/workflows/<file> or
SOURCE/.github/actions/<name> moves to the release when it pins an older one:

    @<commit SHA> # v1.2.3   ->  @SHA # TAG
    @v1.2.3                  ->  @TAG

- A commit SHA moves only with a version comment after it, as Dependabot
  reads it: without one, which release it is cannot be known.
- A moving reference (@main, @v1, @v1.2) is left alone: it was chosen to
  follow a branch or an alias.
- A pin to TAG or to a newer release is left alone: no downgrade.
- The owner and name match whatever their case; the rest of the line (quotes,
  other comments, CRLF line ends) is kept byte for byte.

FILEs are rewritten in place. Each move is printed as one tab-separated line:
FILE, reference, old version, new version. Exit status: 0, or 2 on bad
arguments.
"""
from __future__ import annotations

import re
import sys

RELEASE = re.compile(r"v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?")
COMMIT = re.compile(r"[0-9a-f]{40}(?:[0-9a-f]{24})?")
SOURCE = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")


def release_key(text: str):
    """A sort key for vX.Y.Z[-pre], SemVer order; None for anything else."""
    match = RELEASE.fullmatch(text)
    if not match:
        return None
    major, minor, patch, pre = match.groups()
    # A pre-release sorts before its release; its identifiers compare one by
    # one, numbers below words (SemVer 11).
    identifiers = tuple(
        (0, int(part), "") if part.isdigit() else (1, 0, part) for part in (pre or "").split(".") if part
    )
    return (int(major), int(minor), int(patch), pre is None, identifiers)


def pin_pattern(source: str) -> re.Pattern:
    return re.compile(
        r"(?P<path>" + re.escape(source) + r"/\.github/(?:workflows|actions)/[A-Za-z0-9._/-]+)"
        r"@(?P<ref>[0-9A-Za-z._/-]+)"
        r"(?P<quote>[\"']?)"
        r"(?P<comment>[ \t]+#[ \t]*(?P<version>v?\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)(?![0-9A-Za-z.-]))?",
        re.IGNORECASE,
    )


def same_style(version: str, tag: str) -> str:
    """TAG written like VERSION: with or without its leading v."""
    return tag if version[:1] in ("v", "V") else tag[1:]


def bump(match: re.Match, source: str, tag: str, sha: str, moves: list) -> str:
    ref, quote, comment, version = match["ref"], match["quote"], match["comment"] or "", match["version"]
    new_key = release_key(tag)
    if COMMIT.fullmatch(ref):
        old = version
        if old is None or release_key(old) is None or release_key(old) >= new_key:
            return match[0]
        new_ref = sha
    else:
        old = ref
        if release_key(old) is None or release_key(old) >= new_key:
            return match[0]
        new_ref = same_style(ref, tag)
    if version is not None:
        comment = comment[: -len(version)] + same_style(version, tag)
    # The reference inside SOURCE: .github/workflows/<file> or .github/actions/<name>.
    moves.append((match["path"][len(source) + 1 :], old, tag))
    return f"{match['path']}@{new_ref}{quote}{comment}"


def read(path: str) -> str:
    # surrogateescape and newline="": an unchanged byte stays unchanged.
    with open(path, encoding="utf-8", errors="surrogateescape", newline="") as f:
        return f.read()


def write(path: str, text: str) -> None:
    with open(path, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
        f.write(text)


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        print(__doc__, file=sys.stderr)
        return 2
    source, tag, sha, *files = argv
    if not SOURCE.fullmatch(source):
        print(f"error: SOURCE must be owner/name, not '{source}'", file=sys.stderr)
        return 2
    if release_key(tag) is None or not tag.startswith("v"):
        print(f"error: TAG must be a release vX.Y.Z, not '{tag}'", file=sys.stderr)
        return 2
    if not COMMIT.fullmatch(sha):
        print(f"error: SHA must be a full commit SHA, not '{sha}'", file=sys.stderr)
        return 2
    pattern = pin_pattern(source)
    for path in files:
        text = read(path)
        moves: list = []
        new_text = pattern.sub(lambda m: bump(m, source, tag, sha, moves), text)
        if new_text != text:
            write(path, new_text)
        for reference, old, new in moves:
            print(f"{path}\t{reference}\t{old}\t{new}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
