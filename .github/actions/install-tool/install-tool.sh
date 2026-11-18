#!/usr/bin/env bash
# Install one tool of tools.json into $RUNNER_TEMP and put it on the PATH of
# the job's next steps.
#
# tools.json, next to this script, is the only place a tool's pin lives:
#
#   version   the release (Renovate bumps it)
#   extract   how the download becomes a program:
#               tar.gz, tar.xz   `member` is the program's path in the archive
#               binary           the download is the program, named `member`
#               git              clone the `version` tag of `git`, run its
#                                `installer` with the install directory, and
#                                put that directory's `path` on the PATH
#   url       the release asset ({v} the version without its v, {a} the asset's
#             name for the architecture, from `arch`); `member` takes both too
#   sha256    the asset's SHA-256 per architecture (amd64, arm64)
#   commit    for git, the commit the tag points to (a tag can be moved)
#
# Nothing is installed unless the download matches its pin. After a version
# bump, scripts/update-tool-checksums.py refreshes the pins.
#
# Environment: TOOL (an entry of the manifest), RUNNER_TEMP, GITHUB_PATH.
# TOOLS_MANIFEST replaces the manifest (tests). Needs python3 (reads the
# manifest, opens .tar.xz: the runner image has no jq and no xz), curl,
# sha256sum and tar; git for a git install.
set -euo pipefail

fail() {
  echo "::error::$*"
  exit 1
}

TOOL="${TOOL:-}"
MANIFEST="${TOOLS_MANIFEST:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tools.json}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_PATH:?GITHUB_PATH is required}"

[[ "$TOOL" =~ ^[a-z0-9][a-z0-9-]*$ ]] || fail "unusable tool name '$TOOL'"
command -v python3 > /dev/null || fail "install-tool needs python3 to read its manifest"
[ -f "$MANIFEST" ] || fail "manifest not found: $MANIFEST"

# The manifest entry, resolved for this machine: one value per line, in the
# order read below. An entry this script cannot install is refused here.
spec="$(python3 - "$MANIFEST" "$TOOL" "$(uname -m)" << 'PY'
import json
import sys

manifest, name, machine = sys.argv[1:4]
tools = json.load(open(manifest))
if name not in tools:
    sys.exit(f"unknown tool '{name}' (the manifest lists: {', '.join(sorted(tools))})")
tool = tools[name]
kind = tool.get("extract")
version = tool["version"]
if kind == "git":
    values = [kind, version, tool["git"], tool["commit"], tool["installer"], tool.get("path", "")]
elif kind in ("tar.gz", "tar.xz", "binary"):
    key = {"x86_64": "amd64", "aarch64": "arm64", "arm64": "arm64"}.get(machine)
    if key is None or key not in tool["arch"]:
        sys.exit(f"unsupported arch for {name}: {machine}")
    fields = {"v": version.removeprefix("v"), "a": tool["arch"][key]}
    values = [kind, version, tool["url"].format(**fields), tool["sha256"][key], tool["member"].format(**fields), ""]
else:
    sys.exit(f"{name}: unsupported extract '{kind}'")
for value in values:
    if not isinstance(value, str) or "\n" in value:
        sys.exit(f"{name}: unusable manifest entry")
kind, version, source, pin, member, path = values
if not pin:
    sys.exit(f"{name}: no pin for {machine}")
for relative in (member, path):
    if relative.startswith("/") or ".." in relative.split("/"):
        sys.exit(f"{name}: '{relative}' leaves its directory")
print("\n".join(values))
PY
)" || fail "install-tool cannot install '$TOOL' (see above)"

{
  IFS= read -r KIND
  IFS= read -r VERSION
  IFS= read -r SOURCE
  IFS= read -r PIN
  IFS= read -r MEMBER
  IFS= read -r SUBDIR || true
} <<< "$spec"

INSTALL_DIR="$RUNNER_TEMP/$TOOL"
WORK="$RUNNER_TEMP/install-tool-$TOOL"
rm -rf "$WORK"
mkdir -p "$WORK/out" "$INSTALL_DIR"

if [ "$KIND" = git ]; then
  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$VERSION" "$SOURCE" "$WORK/src" \
    || fail "could not clone $TOOL $VERSION from $SOURCE"
  if [ "$(git -C "$WORK/src" rev-parse HEAD)" != "$PIN" ]; then
    fail "$TOOL $VERSION is not at the pinned commit $PIN — after a version bump, run scripts/update-tool-checksums.py"
  fi
  "$WORK/src/$MEMBER" "$INSTALL_DIR"
  rm -rf "$WORK"
  echo "$INSTALL_DIR${SUBDIR:+/$SUBDIR}" >> "$GITHUB_PATH"
  echo "✅ $TOOL $VERSION installed (commit ${PIN:0:7})"
  exit 0
fi

# GitHub's release downloads answer an occasional 5xx, and without
# --retry-all-errors a refused or reset connection is not retried.
curl -sSfL --retry 5 --retry-delay 5 --retry-all-errors -o "$WORK/asset" "$SOURCE" \
  || fail "could not download $TOOL $VERSION from $SOURCE"
echo "$PIN  $WORK/asset" | sha256sum --check --strict --quiet - \
  || fail "$TOOL $VERSION ($(uname -m)) does not match its pinned SHA-256 — after a version bump, run scripts/update-tool-checksums.py"

case "$KIND" in
  tar.gz)
    tar -xzf "$WORK/asset" -C "$WORK/out" "$MEMBER"
    ;;
  tar.xz)
    python3 -c "import lzma, shutil, sys; shutil.copyfileobj(lzma.open(sys.argv[1]), open(sys.argv[2], 'wb'))" \
      "$WORK/asset" "$WORK/asset.tar"
    tar -xf "$WORK/asset.tar" -C "$WORK/out" "$MEMBER"
    ;;
  binary)
    mv "$WORK/asset" "$WORK/out/$MEMBER"
    ;;
esac
install -m 0755 "$WORK/out/$MEMBER" "$INSTALL_DIR/${MEMBER##*/}"
rm -rf "$WORK"
echo "$INSTALL_DIR" >> "$GITHUB_PATH"
echo "✅ $TOOL $VERSION installed"
