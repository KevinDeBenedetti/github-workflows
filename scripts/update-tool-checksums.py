#!/usr/bin/env python3
"""Refresh the pinned SHA-256 checksums (and git commit) of downloaded tools.

The composite actions and security.yml download release binaries and verify
them against SHA-256 values pinned next to the version:

    # renovate: datasource=github-releases depName=rhysd/actionlint
    ACTIONLINT_VERSION="1.7.11"
    ...
    ACTIONLINT_SHA256_amd64="<sha256>"
    ACTIONLINT_SHA256_arm64="<sha256>"

Renovate bumps the version line but cannot compute the checksums, so the job
fails closed until they are refreshed. After such a bump, run from the
repository root:

    scripts/update-tool-checksums.py           # rewrite the pinned values
    scripts/update-tool-checksums.py --check   # verify only (exit 1 on drift)

Where the project publishes a checksums file, the computed value is also
cross-checked against it. Review the diff before committing.
"""
from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

# prefix → file, release asset URL (per arch key), optional upstream checksums file.
# {v} is the version as written in the file, {a} the asset's arch name.
TOOLS = {
    "ACTIONLINT": {
        "file": ".github/actions/actionlint/action.yml",
        "url": "https://github.com/rhysd/actionlint/releases/download/v{v}/actionlint_{v}_linux_{a}.tar.gz",
        "arch": {"amd64": "amd64", "arm64": "arm64"},
        "sums": "https://github.com/rhysd/actionlint/releases/download/v{v}/actionlint_{v}_checksums.txt",
    },
    "KUBECONFORM": {
        "file": ".github/actions/kubeconform/action.yml",
        "url": "https://github.com/yannh/kubeconform/releases/download/v{v}/kubeconform-linux-{a}.tar.gz",
        "arch": {"amd64": "amd64", "arm64": "arm64"},
        "sums": "https://github.com/yannh/kubeconform/releases/download/v{v}/CHECKSUMS",
    },
    "SHELLCHECK": {
        "file": ".github/actions/shellcheck/action.yml",
        "url": "https://github.com/koalaman/shellcheck/releases/download/v{v}/shellcheck-v{v}.linux.{a}.tar.xz",
        "arch": {"amd64": "x86_64", "arm64": "aarch64"},
        "sums": None,  # ShellCheck publishes no checksums file
    },
    "GITLEAKS": {
        "file": ".github/workflows/security.yml",
        "url": "https://github.com/gitleaks/gitleaks/releases/download/v{v}/gitleaks_{v}_linux_{a}.tar.gz",
        "arch": {"amd64": "x64", "arm64": "arm64"},
        "sums": "https://github.com/gitleaks/gitleaks/releases/download/v{v}/gitleaks_{v}_checksums.txt",
    },
}
# prefix → file, git repository: the pinned <PREFIX>_COMMIT must be the tag's commit.
GIT_TAGS = {
    "BATS": {
        "file": ".github/actions/bats/action.yml",
        "repo": "https://github.com/bats-core/bats-core.git",
    },
}


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=120) as r:  # noqa: S310 — fixed https URLs
        return r.read()


def version_of(text: str, prefix: str, path: str) -> str:
    m = re.search(rf'^\s*{prefix}_VERSION="([^"]+)"', text, re.M)
    if not m:
        sys.exit(f"{path}: {prefix}_VERSION not found")
    return m.group(1)


def replace_value(text: str, var: str, value: str, path: str) -> str:
    pattern = re.compile(rf'^(\s*{var}=")[^"]*(")', re.M)
    if not pattern.search(text):
        sys.exit(f"{path}: {var} not found")
    return pattern.sub(rf"\g<1>{value}\g<2>", text, count=1)


def current_value(text: str, var: str) -> str | None:
    m = re.search(rf'^\s*{var}="([^"]*)"', text, re.M)
    return m.group(1) if m else None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="verify only, do not rewrite files")
    args = parser.parse_args()

    drift = 0
    texts: dict[str, str] = {}

    for prefix, tool in TOOLS.items():
        path = tool["file"]
        text = texts.setdefault(path, Path(path).read_text())
        v = version_of(text, prefix, path)
        bare = v.removeprefix("v")
        upstream = fetch(tool["sums"].format(v=bare)).decode() if tool["sums"] else None
        for key, arch in tool["arch"].items():
            url = tool["url"].format(v=bare, a=arch)
            digest = hashlib.sha256(fetch(url)).hexdigest()
            asset = url.rsplit("/", 1)[1]
            if upstream is not None and not re.search(rf"^{digest}\s+\*?{re.escape(asset)}$", upstream, re.M):
                sys.exit(f"{prefix} {v} {key}: computed {digest} is NOT in the upstream checksums file — investigate before pinning")
            var = f"{prefix}_SHA256_{key}"
            if current_value(text, var) != digest:
                drift += 1
                print(f"{path}: {var} → {digest}")
                text = replace_value(text, var, digest, path)
            else:
                print(f"{path}: {var} up to date ({v})")
        texts[path] = text

    for prefix, tool in GIT_TAGS.items():
        path = tool["file"]
        text = texts.setdefault(path, Path(path).read_text())
        v = version_of(text, prefix, path)
        out = subprocess.run(
            ["git", "ls-remote", tool["repo"], f"refs/tags/{v}", f"refs/tags/{v}^{{}}"],
            check=True, capture_output=True, text=True,
        ).stdout.split("\n")
        refs = dict(reversed(line.split("\t")) for line in out if line)
        commit = refs.get(f"refs/tags/{v}^{{}}") or refs.get(f"refs/tags/{v}")
        if not commit:
            sys.exit(f"{prefix}: tag {v} not found in {tool['repo']}")
        var = f"{prefix}_COMMIT"
        if current_value(text, var) != commit:
            drift += 1
            print(f"{path}: {var} → {commit}")
            text = replace_value(text, var, commit, path)
        else:
            print(f"{path}: {var} up to date ({v})")
        texts[path] = text

    if args.check:
        if drift:
            print(f"\n{drift} pinned value(s) out of date — run without --check to refresh.")
            return 1
        return 0
    for path, text in texts.items():
        Path(path).write_text(text)
    print("\nDone." if drift else "\nAll pinned values already up to date.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
