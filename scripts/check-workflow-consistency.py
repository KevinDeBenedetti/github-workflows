#!/usr/bin/env python3
"""Consistency checks for the reusable workflows of this repository.

1. Inputs duplicated between `workflow_call` and `workflow_dispatch` must stay
   in sync (same names, types and defaults). GitHub has no shared input
   definition, so the two blocks are maintained by hand and drift silently.
   Descriptions and `required` may differ.

2. Every reference to one of this repo's composite actions from a workflow,
   and every reference to this repo's workflows or actions from an example,
   must be pinned to the current release (`@v<manifest version>`), carry the
   `# x-release-please-version` marker, and live in a file listed in the
   release-please `extra-files` — otherwise release-please stops bumping it
   and callers pinned to a release silently run another version of the action
   (or copy an example that tracks the mutable `main`).

Usage: check-workflow-consistency.py [files...]   (no args → all workflows)
Run from the repository root.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import yaml

WORKFLOWS = Path(".github/workflows")
EXAMPLES = Path("examples")
RELEASE_CONFIG = Path(".github/release/release-please-config.json")
MANIFEST = Path(".github/release/.release-please-manifest.json")
ACTION_REF = re.compile(
    r"uses:\s*KevinDeBenedetti/github-workflows/\.github/actions/[\w-]+@(?P<ref>\S+)(?P<rest>.*)$"
)
# Examples are copied into other repos: their workflow refs are pinned too.
EXAMPLE_REF = re.compile(
    r"uses:\s*KevinDeBenedetti/github-workflows/\.github/(?:actions|workflows)/[\w.-]+@(?P<ref>\S+)(?P<rest>.*)$"
)


def triggers(doc: dict) -> dict:
    # PyYAML (YAML 1.1) parses the bare key `on` as the boolean True.
    return doc.get("on", doc.get(True)) or {}


def norm_default(value):
    if value is None:
        return ""
    if isinstance(value, bool):
        return str(value).lower()
    return str(value)


def check_inputs(path: Path, doc: dict) -> list[str]:
    on = triggers(doc)
    if not isinstance(on, dict):
        return []
    call = (on.get("workflow_call") or {}).get("inputs") or {}
    dispatch = (on.get("workflow_dispatch") or {}).get("inputs") or {}
    if not call or not dispatch:
        return []
    errors = []
    for name in sorted(set(call) ^ set(dispatch)):
        where = "workflow_call" if name in call else "workflow_dispatch"
        errors.append(f"{path}: input '{name}' only declared under {where}")
    for name in sorted(set(call) & set(dispatch)):
        c, d = call[name], dispatch[name]
        if c.get("type") != d.get("type"):
            errors.append(
                f"{path}: input '{name}' type differs "
                f"(workflow_call: {c.get('type')}, workflow_dispatch: {d.get('type')})"
            )
        if norm_default(c.get("default")) != norm_default(d.get("default")):
            errors.append(
                f"{path}: input '{name}' default differs "
                f"(workflow_call: {c.get('default')!r}, workflow_dispatch: {d.get('default')!r})"
            )
    return errors


def check_action_refs(
    path: Path, version: str, extra_files: set[str], pattern: re.Pattern = ACTION_REF
) -> list[str]:
    errors = []
    for lineno, line in enumerate(path.read_text().splitlines(), 1):
        m = pattern.search(line)
        if not m:
            continue
        where = f"{path}:{lineno}"
        if m.group("ref") != f"v{version}":
            errors.append(f"{where}: internal reference pinned to @{m.group('ref')}, expected @v{version}")
        if "x-release-please-version" not in m.group("rest"):
            errors.append(f"{where}: missing '# x-release-please-version' marker")
        if path.as_posix() not in extra_files:
            errors.append(f"{where}: {path} is not listed in extra-files of {RELEASE_CONFIG}")
    return errors


def main(argv: list[str]) -> int:
    files = [Path(a) for a in argv] if argv else sorted(WORKFLOWS.glob("*.y*ml"))
    files = [f for f in files if f.parent == WORKFLOWS and f.suffix in (".yml", ".yaml")]
    examples = sorted(EXAMPLES.glob("*.y*ml")) if not argv else [
        Path(a) for a in argv if Path(a).parent == EXAMPLES and Path(a).suffix in (".yml", ".yaml")
    ]

    version = json.loads(MANIFEST.read_text())["."]
    config = json.loads(RELEASE_CONFIG.read_text())
    extra_files = {
        e["path"] if isinstance(e, dict) else e
        for e in config["packages"]["."].get("extra-files", [])
    }

    errors: list[str] = []
    for path in files:
        doc = yaml.safe_load(path.read_text()) or {}
        errors += check_inputs(path, doc)
        errors += check_action_refs(path, version, extra_files)
    for path in examples:
        errors += check_action_refs(path, version, extra_files, EXAMPLE_REF)

    for e in errors:
        print(f"ERROR: {e}")
    if errors:
        print(f"\n{len(errors)} problem(s) found.")
        return 1
    print(f"✔ {len(files)} workflow(s) and {len(examples)} example(s) consistent.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
