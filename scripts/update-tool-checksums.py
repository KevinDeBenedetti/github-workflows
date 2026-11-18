#!/usr/bin/env python3
"""Refresh and verify the pins of the tools the actions download.

.github/actions/install-tool/tools.json is the one place a tool's pin lives:
version, release asset URL ({v} the version, {a} the asset's arch name), arch
map, how the asset is extracted, upstream checksums, and the SHA-256 per arch
(or, for a git install, the tag's commit). Renovate bumps the version there
(JSONata custom manager, renovate.json), and the install-tool action reads the
file at run time: nothing else holds a copy.

After a version bump, run from the repository root:

    scripts/update-tool-checksums.py                 # refresh the manifest's pins
    scripts/update-tool-checksums.py --check         # verify only (exit 1 on drift)
    scripts/update-tool-checksums.py --check --since <commit>
                                                     # CI: only when a pin changed since

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

MANIFEST = ".github/actions/install-tool/tools.json"
# Besides the manifest, a change to these re-runs the check (--since).
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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="verify only, do not rewrite files")
    parser.add_argument("--since", metavar="COMMIT", help="do nothing unless the manifest, this script or ci-cd.yml changed since COMMIT")
    args = parser.parse_args()

    tools = load_manifest()
    if args.since:
        # CI: every asset is downloaded again, so skip when neither the pins
        # nor what checks them changed since the given commit.
        changed = subprocess.run(
            ["git", "diff", "--name-only", args.since, "HEAD", "--", MANIFEST, *WATCHED],
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

    if args.check:
        if drift:
            print(f"\n{drift} pinned value(s) out of date — run without --check to refresh.")
            return 1
        return 0
    if drift:
        Path(MANIFEST).write_text(json.dumps(tools, indent=2) + "\n")
    print("\nDone." if drift else "\nAll pinned values already up to date.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
