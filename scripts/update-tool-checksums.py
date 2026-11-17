#!/usr/bin/env python3
"""Keep the downloaded tools' pins in step with .github/tools.json.

.github/tools.json is the one place a tool's pin lives: version, release asset
URL ({v} the version, {a} the asset's arch name), arch map, upstream checksums,
and the SHA-256 per arch (or, for a git install, the tag's commit). Renovate
bumps the version there (JSONata custom manager, renovate.json). The composite
actions cannot read it at run time, so each install block holds a copy:

    ACTIONLINT_VERSION="1.7.11"
    ACTIONLINT_SHA256_amd64="<sha256>"
    ACTIONLINT_SHA256_arm64="<sha256>"

After a version bump, run from the repository root:

    scripts/update-tool-checksums.py                 # refresh the manifest, copy it into the actions
    scripts/update-tool-checksums.py --check         # verify only (exit 1 on drift)
    scripts/update-tool-checksums.py --check --since <commit>
                                                     # CI: only when a pin changed since
    scripts/update-tool-checksums.py --consistency   # offline: the actions agree with the manifest
    scripts/update-tool-checksums.py --list-files    # the manifest and the files holding a pin

Where the project publishes checksums (one file per release, or one per asset
for lychee), the computed value is also cross-checked against them (Claude
Code: the platforms.<platform>.checksum values of the release's
manifest.json). Review the diff before committing.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

MANIFEST = ".github/tools.json"
# Besides the manifest and the files holding a pin, a change to these re-runs
# the check (--since).
WATCHED = ["scripts/update-tool-checksums.py", ".github/workflows/ci-cd.yml"]


def load_manifest() -> dict:
    return json.loads(Path(MANIFEST).read_text())


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=120) as r:  # noqa: S310 — fixed https URLs
        return r.read()


def sha256_of(url: str) -> str:
    # Streamed: some assets (the Claude Code binary) weigh hundreds of MB.
    digest = hashlib.sha256()
    with urllib.request.urlopen(url, timeout=300) as r:  # noqa: S310 — fixed https URLs
        for chunk in iter(lambda: r.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def replace_value(text: str, var: str, value: str, path: str) -> str:
    pattern = re.compile(rf'^(\s*{var}=")[^"]*(")', re.M)
    if not pattern.search(text):
        sys.exit(f"{path}: {var} not found")
    return pattern.sub(rf"\g<1>{value}\g<2>", text, count=1)


def current_value(text: str, var: str) -> str | None:
    m = re.search(rf'^\s*{var}="([^"]*)"', text, re.M)
    return m.group(1) if m else None


def consistency(tools: dict, texts: dict[str, str]) -> list[str]:
    """What each install block gets wrong against the manifest (no network)."""
    problems = []
    for prefix, tool in tools.items():
        path = tool["file"]
        if not Path(path).is_file():
            problems.append(f"{path}: missing ({prefix})")
            continue
        text = texts.setdefault(path, Path(path).read_text())
        expected = {f"{prefix}_VERSION": tool["version"]}
        if "git" in tool:
            expected[f"{prefix}_COMMIT"] = tool["commit"]
        else:
            expected.update({f"{prefix}_SHA256_{key}": value for key, value in tool["sha256"].items()})
            url = tool["url"].replace("{v}", f"${{{prefix}_VERSION}}").replace("{a}", f"${{{tool['archVar']}}}")
            if url not in text:
                problems.append(f"{path}: downloads another URL than the manifest's {url}")
            for key, arch in tool["arch"].items():
                if not re.search(rf"\b{tool['archVar']}={re.escape(arch)}\b", text):
                    problems.append(f"{path}: no {tool['archVar']}={arch} for {key}")
        for var, value in expected.items():
            found = current_value(text, var)
            if found is None:
                problems.append(f"{path}: {var} not found")
            elif found != value:
                problems.append(f"{path}: {var}=\"{found}\", the manifest says \"{value}\"")
        if re.search(rf"# renovate: .*depName={re.escape(tool['package'])}\s", text):
            problems.append(f"{path}: a renovate comment pins {tool['package']} here too — the manifest is its only pin")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="verify only, do not rewrite files")
    parser.add_argument("--consistency", action="store_true", help="offline: check that the actions hold the manifest's pins, and exit")
    parser.add_argument("--list-files", action="store_true", help="print the manifest and the files holding a pin, one per line, and exit")
    parser.add_argument("--since", metavar="COMMIT", help="do nothing unless the manifest, a file holding a pin, this script or ci-cd.yml changed since COMMIT")
    args = parser.parse_args()

    tools = load_manifest()
    pinned_files = sorted({MANIFEST, *(tool["file"] for tool in tools.values())})
    if args.list_files:
        print("\n".join(pinned_files))
        return 0
    texts: dict[str, str] = {}
    if args.consistency:
        problems = consistency(tools, texts)
        for problem in problems:
            print(problem)
        if problems:
            print(f"\n{len(problems)} problem(s): run scripts/update-tool-checksums.py to copy the manifest into the actions (a URL or an arch is fixed by hand).")
            return 1
        print(f"✔ {len(tools)} tool(s): the actions hold the pins of {MANIFEST}.")
        return 0
    if args.since:
        # CI: every asset is downloaded again, so skip when nothing that
        # holds or checks a pin changed since the given commit.
        changed = subprocess.run(
            ["git", "diff", "--name-only", args.since, "HEAD", "--", *pinned_files, *WATCHED],
            check=True, capture_output=True, text=True,
        ).stdout.split()
        if not changed:
            print(f"No pinned tool changed since {args.since[:7]}: nothing to verify.")
            return 0
        print("Changed: " + " ".join(changed))

    drift = 0
    for prefix, tool in tools.items():
        v = tool["version"]
        if "git" in tool:
            out = subprocess.run(
                ["git", "ls-remote", tool["git"], f"refs/tags/{v}", f"refs/tags/{v}^{{}}"],
                check=True, capture_output=True, text=True,
            ).stdout.split("\n")
            refs = dict(reversed(line.split("\t")) for line in out if line)
            commit = refs.get(f"refs/tags/{v}^{{}}") or refs.get(f"refs/tags/{v}")
            if not commit:
                sys.exit(f"{prefix}: tag {v} not found in {tool['git']}")
            if tool["commit"] != commit:
                drift += 1
                print(f"{MANIFEST}: {prefix} commit → {commit}")
                tool["commit"] = commit
            else:
                print(f"{MANIFEST}: {prefix} commit up to date ({v})")
            continue
        bare = v.removeprefix("v")
        sums = tool.get("sums")
        # One checksums file per release, or one per asset when its URL has {a}.
        per_asset = "{a}" in (sums or "")
        upstream = fetch(sums.format(v=bare)).decode() if sums and not per_asset else None
        release = json.loads(fetch(tool["releaseManifest"].format(v=bare))) if tool.get("releaseManifest") else None
        for key, arch in tool["arch"].items():
            url = tool["url"].format(v=bare, a=arch)
            if per_asset:
                upstream = fetch(sums.format(v=bare, a=arch)).decode()
            digest = sha256_of(url)
            asset = url.rsplit("/", 1)[1]
            if upstream is not None and not re.search(rf"^{digest}\s+\*?{re.escape(asset)}$", upstream, re.M):
                sys.exit(f"{prefix} {v} {key}: computed {digest} is NOT in the upstream checksums file — investigate before pinning")
            if release is not None:
                listed = release.get("platforms", {}).get(arch, {}).get("checksum")
                if listed != digest:
                    sys.exit(f"{prefix} {v} {key}: computed {digest} does not match the release manifest ({listed}) — investigate before pinning")
            if tool["sha256"].get(key) != digest:
                drift += 1
                print(f"{MANIFEST}: {prefix} sha256 {key} → {digest}")
                tool["sha256"][key] = digest
            else:
                print(f"{MANIFEST}: {prefix} sha256 {key} up to date ({v})")

    # The actions' copies, against the manifest as refreshed above.
    problems = consistency(tools, texts)
    if args.check:
        for problem in problems:
            print(problem)
        if drift or problems:
            print(f"\n{drift + len(problems)} pinned value(s) out of date — run without --check to refresh.")
            return 1
        return 0
    for prefix, tool in tools.items():
        path = tool["file"]
        text = texts[path]
        text = replace_value(text, f"{prefix}_VERSION", tool["version"], path)
        if "git" in tool:
            text = replace_value(text, f"{prefix}_COMMIT", tool["commit"], path)
        else:
            for key, value in tool["sha256"].items():
                text = replace_value(text, f"{prefix}_SHA256_{key}", value, path)
        texts[path] = text
    Path(MANIFEST).write_text(json.dumps(tools, indent=2) + "\n")
    for path, text in texts.items():
        Path(path).write_text(text)
    # What the copy cannot fix (a URL or an arch map): the action is edited by hand.
    remaining = consistency(tools, {})
    for problem in remaining:
        print(problem)
    print("\nDone." if drift else "\nAll pinned values already up to date.")
    return 1 if remaining else 0


if __name__ == "__main__":
    sys.exit(main())
