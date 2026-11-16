#!/usr/bin/env python3
"""Consistency checks for the reusable workflows of this repository.

1. Inputs duplicated between `workflow_call` and `workflow_dispatch` must stay
   in sync (same names, types and defaults). GitHub has no shared input
   definition, so the two blocks are maintained by hand and drift silently.
   Descriptions and `required` may differ.

2. A workflow references this repo's composite actions with the
   self-repository syntax (`uses: $/.github/actions/<name>`), which GitHub
   resolves to the commit the workflow itself runs from — so a caller pinned
   to a release runs that release's actions, with no pin to bump. A remote
   self-reference (`KevinDeBenedetti/github-workflows/.github/actions/…@ref`)
   is an error: it would have to be bumped in .github/workflows/ on every
   release, which the release job's GITHUB_TOKEN can never push.

3. Every reference to this repo's workflows or actions from an example (copied
   into other repositories) must be pinned to the current release
   (`@v<manifest version>`), carry the `# x-release-please-version` marker, and
   live in a file listed in the release-please `extra-files` — otherwise
   release-please stops bumping it and callers copy an example that tracks the
   mutable `main`.

4. Catalogs (full run only): every reusable workflow (`workflow_call`) has its
   page in docs/workflows/ and a row in the workflow tables of README.md and
   docs/getting-started.md; every composite action has its page in
   docs/actions/ and a row in the actions table of docs/getting-started.md.
   Nothing else reminds a contributor of these files.

5. The `with:` keys a workflow or a composite action passes to one of this
   repo's actions (`uses: $/.github/actions/<name>` or `./.github/actions/…`)
   must be inputs that action declares. actionlint does not read `$/` yet, and
   GitHub only warns about an unknown input at run time.

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
ACTIONS = Path(".github/actions")
EXAMPLES = Path("examples")
README = Path("README.md")
GETTING_STARTED = Path("docs/getting-started.md")
LOCAL_ACTION = re.compile(r"^(?:\$|\.)/\.github/actions/(?P<name>[\w-]+)$")
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


def check_self_refs(path: Path) -> list[str]:
    errors = []
    for lineno, line in enumerate(path.read_text().splitlines(), 1):
        m = ACTION_REF.search(line)
        if m:
            name = line.split("/.github/actions/", 1)[1].split("@", 1)[0]
            errors.append(
                f"{path}:{lineno}: remote self-reference — use `uses: $/.github/actions/{name}`"
            )
    return errors


def is_reusable(doc: dict) -> bool:
    on = triggers(doc)
    return isinstance(on, dict) and "workflow_call" in on


def table_rows(path: Path) -> list[str]:
    if not path.exists():
        return []
    return [line for line in path.read_text().splitlines() if line.startswith("|")]


def check_catalogs(reusable: list[Path], actions: list[str]) -> list[str]:
    errors = []
    readme, started = table_rows(README), table_rows(GETTING_STARTED)
    for path in reusable:
        page = Path("docs/workflows") / f"{path.stem}.md"
        if not page.exists():
            errors.append(f"{path}: no documentation page {page}")
        for catalog, rows in ((README, readme), (GETTING_STARTED, started)):
            if not any(f"`{path.name}`" in row for row in rows):
                errors.append(f"{path}: no row for `{path.name}` in the workflow table of {catalog}")
    for name in actions:
        page = Path("docs/actions") / f"{name}.md"
        if not page.exists():
            errors.append(f"{ACTIONS / name}: no documentation page {page}")
        if not any(f"(actions/{name}.md)" in row for row in started):
            errors.append(f"{ACTIONS / name}: no row linking actions/{name}.md in the actions table of {GETTING_STARTED}")
    return errors


def action_inputs(name: str) -> set[str] | None:
    for filename in ("action.yml", "action.yaml"):
        path = ACTIONS / name / filename
        if path.exists():
            return set((yaml.safe_load(path.read_text()) or {}).get("inputs") or {})
    return None


def steps_of(doc: dict) -> list[dict]:
    """The steps of a workflow's jobs, or of a composite action."""
    steps = list((doc.get("runs") or {}).get("steps") or [])
    for job in (doc.get("jobs") or {}).values():
        steps += (job or {}).get("steps") or []
    return [s for s in steps if isinstance(s, dict)]


def check_with_keys(path: Path, doc: dict) -> list[str]:
    errors = []
    for step in steps_of(doc):
        m = LOCAL_ACTION.match(str(step.get("uses", "")))
        if not m:
            continue
        declared = action_inputs(m.group("name"))
        if declared is None:
            errors.append(f"{path}: `uses: {step['uses']}` — no such action in {ACTIONS}")
            continue
        for key in sorted(set(step.get("with") or {}) - declared):
            errors.append(f"{path}: `{key}` is not an input of the {m.group('name')} action")
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
    reusable = []
    for path in files:
        doc = yaml.safe_load(path.read_text()) or {}
        errors += check_inputs(path, doc)
        errors += check_self_refs(path)
        errors += check_with_keys(path, doc)
        if is_reusable(doc):
            reusable.append(path)
    if not argv:
        actions = sorted(p.parent.name for p in ACTIONS.glob("*/action.y*ml"))
        for name in actions:
            action_file = next((ACTIONS / name).glob("action.y*ml"))
            errors += check_with_keys(action_file, yaml.safe_load(action_file.read_text()) or {})
        errors += check_catalogs(reusable, actions)
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
