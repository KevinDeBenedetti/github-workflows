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

The description is model output written from untrusted repository content, so
it is treated as data, not as GitHub markup with side effects. Outside code
spans and fenced code blocks, `neutralize` decodes HTML entities (so `&#64;`
cannot smuggle a mention), removes HTML and images (GitHub fetches image URLs
through its proxy when the body is viewed), turns links into their text, and
wraps @mentions, issue references and URLs in code spans: no notification, no
cross-reference, no "Closes #N" on merge, no clickable link. Control, zero-width
and bidirectional characters, which could hide or reorder text, are dropped
everywhere.

Exit status: 0 written, 1 unusable description or body too long, 2 usage.
"""
from __future__ import annotations

import html
import re
import sys

START = "<!-- pr-description:start (rewritten on every push: write your own notes outside this block) -->"
END = "<!-- pr-description:end -->"
# Any start marker, whatever its comment text, up to the first end marker.
BLOCK = re.compile(r"<!--\s*pr-description:start\b.*?-->.*?<!--\s*pr-description:end\s*-->", re.S)
MARKER = re.compile(r"<!--\s*pr-description:(?:start|end)\b.*?-->", re.S)
# A model sometimes wraps its whole answer in a code fence.
FENCE = re.compile(r"\A```[\w-]*[ \t]*\r?\n(?P<inner>.*?)\r?\n```\s*\Z", re.S)
# An optional section that only says "None" breaks the uniform layout: these
# sections appear only when they apply. Dropped when nothing else follows it.
EMPTY_OPTIONAL = re.compile(
    r"^## (?:Breaking changes|Notes for reviewers)[ \t]*\r?\n"
    r"\s*(?:[-*][ \t]+)?(?:none|n/a|nothing to (?:note|report))\.?[ \t]*(?:\r?\n|\Z)"
    r"\s*(?=^## |\Z)",
    re.I | re.M,
)
MAX_DESCRIPTION = 20_000  # characters: nobody reads a longer description
BODY_LIMIT = 65_536  # GitHub rejects a longer pull request body

# Code is left as it is: GitHub renders neither markup nor references inside it.
FENCED_BLOCK = re.compile(r"^(`{3,}|~{3,})[^\n]*\n.*?^\1[ \t]*$", re.S | re.M)
INLINE_CODE = re.compile(r"`+[^`\n]+`+")

# Characters removed everywhere, code included: C0 and C1 controls (apart from
# tab and newline), zero-width characters, bidirectional overrides and
# isolates, the line and paragraph separators.
UNSAFE_CHARS = re.compile(
    "[\u0000-\u0008\u000b-\u001f\u007f-\u009f​-‏-‮⁠-⁤⁦-⁩﻿]"
)
HTML_COMMENT = re.compile(r"<!--.*?-->", re.S)
HTML_TAG = re.compile(r"</?[A-Za-z][^<>]*>")
# ![alt](url) keeps its alt text; [text](url "title") and [text][ref] keep their text.
IMAGE = re.compile(r"!\[([^\]]*)\]\((?:[^()]|\([^()]*\))*\)")
LINK = re.compile(r"\[([^\]]+)\]\((?:[^()]|\([^()]*\))*\)")
REF_LINK = re.compile(r"\[([^\]]+)\]\[[^\]]*\]")
REF_DEFINITION = re.compile(r"^[ \t]*\[[^\]]+\]:[ \t]+\S+[^\n]*$", re.M)
# A bare URL, as GitHub autolinks it, without trailing punctuation. Issue and
# pull request URLs are among them: in code they neither link nor close.
URL = re.compile(r"(?<![\w`])(?:https?://|www\.)[^\s<>()\[\]`]*[^\s<>()\[\]`.,;:!?'\"]")
# owner/repo#12, #12 and GH-12, where GitHub would link them.
ISSUE_REF = re.compile(r"(?<![\w`#&/.-])(?:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#\d+\b|(?<![\w`-])GH-\d+\b")
# @user or @org/team, not the @ of an e-mail address.
MENTION = re.compile(r"(?<![\w`@/.-])@[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})(?:/[A-Za-z0-9_-]+)?")


def read(path: str) -> str:
    # newline="": keep CRLF as is, so an unchanged body stays byte-identical.
    with open(path, encoding="utf-8", newline="") as f:
        return f.read()


def write(path: str, text: str) -> None:
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)


def as_code(match: re.Match) -> str:
    return f"`{match.group(0)}`"


def wrap_outside_code(pattern: re.Pattern, text: str) -> str:
    """Wrap each match of `pattern` in a code span, skipping existing spans."""
    return map_inline(text, lambda part: pattern.sub(as_code, part))


def neutralize_prose(text: str) -> str:
    """Disarm GitHub markup with side effects, in text outside code."""
    # Decoded first: &#64; or &lt;img&gt; must not survive as a mention or a tag.
    text = UNSAFE_CHARS.sub("", html.unescape(text))
    text = HTML_COMMENT.sub("", text)
    text = HTML_TAG.sub("", text)
    text = IMAGE.sub(r"\1", text)
    text = LINK.sub(r"\1", text)
    text = REF_LINK.sub(r"\1", text)
    text = REF_DEFINITION.sub("", text)
    # One pattern at a time, each skipping the spans the previous one made.
    for pattern in (URL, ISSUE_REF, MENTION):
        text = wrap_outside_code(pattern, text)
    return text


def map_prose(text: str, transform) -> str:
    """Apply `transform` to the parts of `text` that are not code."""
    out = []
    position = 0
    for block in FENCED_BLOCK.finditer(text):
        out.append(map_inline(text[position : block.start()], transform))
        out.append(block.group(0))
        position = block.end()
    out.append(map_inline(text[position:], transform))
    return "".join(out)


def map_inline(text: str, transform) -> str:
    out = []
    position = 0
    for span in INLINE_CODE.finditer(text):
        out.append(transform(text[position : span.start()]))
        out.append(span.group(0))
        position = span.end()
    out.append(transform(text[position:]))
    return "".join(out)


def neutralize(text: str) -> str:
    text = UNSAFE_CHARS.sub("", text.replace("\r\n", "\n").replace("\r", "\n"))
    return map_prose(text, neutralize_prose)


def clean(text: str) -> str:
    text = text.strip()
    fenced = FENCE.match(text)
    if fenced:
        text = fenced.group("inner").strip()
    # The description must not open or close the block by itself.
    text = MARKER.sub("", text).strip()
    text = neutralize(text).strip()
    text = EMPTY_OPTIONAL.sub("", text).strip()
    if len(text) > MAX_DESCRIPTION:
        size = len(text)
        cut = text.rfind("\n", 0, MAX_DESCRIPTION)
        text = text[: cut if cut > 0 else MAX_DESCRIPTION].rstrip()
        text += f"\n\n_(description truncated: {size} characters, {MAX_DESCRIPTION} kept)_"
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
