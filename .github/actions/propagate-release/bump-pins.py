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

The hooks of SOURCE in a prek.toml move the same way: the first `rev = ` line
after `repo = "https://github.com/SOURCE"` (comment and blank lines between
them allowed) moves when it is an older release, written with or without the
v as before. Its reference is .pre-commit-hooks.yaml, SOURCE's hook manifest.

So do the Renovate presets of SOURCE in a Renovate config file (renovate.json,
.renovaterc or .renovaterc.json, each also as .jsonc or .json5): a quoted
"github>SOURCE#v1.2.3", "github>SOURCE:name#v1.2.3" or
"github>SOURCE//path/name#v1.2.3" moves its tag. Its reference is the preset
file Renovate reads in SOURCE (default.json, name.json, path/name.json).

FILEs are rewritten in place. Each move is printed as one tab-separated line:
FILE, reference, old version, new version. Exit status: 0, or 2 on bad
arguments.
"""
from __future__ import annotations

import os
import re
import sys

# The config files Renovate reads that can extend a preset (package.json
# aside: a `renovate` key there is not worth parsing for one pin).
RENOVATE_CONFIGS = {
    "renovate.json", "renovate.jsonc", "renovate.json5",
    ".renovaterc", ".renovaterc.json", ".renovaterc.jsonc", ".renovaterc.json5",
}
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


def hook_pattern(source: str) -> re.Pattern:
    """The rev of SOURCE's hooks in a prek.toml [[repos]] entry."""
    return re.compile(
        r"(?P<head>^[ \t]*repo[ \t]*=[ \t]*([\"'])https://github\.com/" + re.escape(source) + r"(?:\.git)?\2[ \t]*\r?\n"
        r"(?:[ \t]*(?:#[^\r\n]*)?\r?\n)*"
        r"[ \t]*rev[ \t]*=[ \t]*(?P<quote>[\"']))(?P<ref>[0-9A-Za-z._/-]+)(?P=quote)",
        re.IGNORECASE | re.MULTILINE,
    )


def bump_rev(match: re.Match, tag: str, moves: list, reference: str) -> str:
    """A release written alone (a hook rev, a preset tag) moved to TAG."""
    old = match["ref"]
    if release_key(old) is None or release_key(old) >= release_key(tag):
        return match[0]
    moves.append((reference, old, tag))
    return f"{match['head']}{same_style(old, tag)}{match['quote']}"


def preset_pattern(source: str) -> re.Pattern:
    """A Renovate preset of SOURCE pinned to a ref, as a quoted string."""
    return re.compile(
        r"(?P<head>(?P<quote>[\"'])github>" + re.escape(source)
        + r"(?P<preset>//[A-Za-z0-9._/-]+|:[A-Za-z0-9._+/-]+)?#)"
        r"(?P<ref>[0-9A-Za-z._/-]+)(?P=quote)",
        re.IGNORECASE,
    )


def preset_file(preset: str | None) -> str:
    """The file of SOURCE a preset names, as Renovate resolves it."""
    if not preset:
        name = "default"
    elif preset.startswith("//"):
        name = preset[2:]
    else:
        # `:name/sub` is the preset `sub` inside name.json.
        name = preset[1:].split("/", 1)[0]
    return name if name.endswith((".json", ".json5")) else f"{name}.json"


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
    hooks = hook_pattern(source)
    presets = preset_pattern(source)
    for path in files:
        text = read(path)
        moves: list = []
        new_text = pattern.sub(lambda m: bump(m, source, tag, sha, moves), text)
        if path.endswith("prek.toml"):
            new_text = hooks.sub(lambda m: bump_rev(m, tag, moves, ".pre-commit-hooks.yaml"), new_text)
        if os.path.basename(path) in RENOVATE_CONFIGS:
            new_text = presets.sub(lambda m: bump_rev(m, tag, moves, preset_file(m["preset"])), new_text)
        if new_text != text:
            write(path, new_text)
        for reference, old, new in moves:
            print(f"{path}\t{reference}\t{old}\t{new}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
