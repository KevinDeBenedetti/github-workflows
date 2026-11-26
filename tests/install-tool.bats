#!/usr/bin/env bats
# Tests for .github/actions/install-tool/install-tool.sh, with a manifest whose
# assets are local files (file:// URLs): curl, sha256sum and tar are the real
# ones. uname is a fake that answers the architecture under test, and git a
# fake that copies a directory and answers the commit recorded in it.

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/install-tool/install-tool.sh"
REAL_MANIFEST="$BATS_TEST_DIRNAME/../.github/actions/install-tool/tools.json"

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

# program FILE: an executable that prints "<its name> runs".
program() {
  printf '#!/bin/sh\necho "%s runs"\n' "${1##*/}" > "$1"
  chmod +x "$1"
}

setup() {
  cd "$BATS_TEST_TMPDIR"
  export RUNNER_TEMP="$BATS_TEST_TMPDIR/runner" GITHUB_PATH="$BATS_TEST_TMPDIR/github-path"
  export TOOLS_MANIFEST="$BATS_TEST_TMPDIR/tools.json" MACHINE=x86_64
  export GIT_LOG="$BATS_TEST_TMPDIR/git.log"
  mkdir -p "$RUNNER_TEMP" bin dist
  : > "$GITHUB_PATH"
  printf '#!/bin/sh\necho "$MACHINE"\n' > bin/uname
  # git clone … SOURCE DEST copies SOURCE; git -C DIR rev-parse HEAD prints
  # the commit recorded in DIR/HEAD-COMMIT.
  cat > bin/git << 'SH'
#!/bin/sh
echo "$*" >> "$GIT_LOG"
case " $* " in
  *" clone "*)
    for last; do prev="${dest:-}"; dest="$last"; done
    cp -R "$prev" "$dest"
    ;;
  *" rev-parse HEAD "*)
    cat "$2/HEAD-COMMIT"
    ;;
  *) echo "fake git: unexpected $*" >&2; exit 1 ;;
esac
SH
  chmod +x bin/uname bin/git
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  # One asset per extraction kind and architecture.
  local arch
  for arch in x86_64 aarch64; do
    mkdir -p "stage/gz-$arch" "stage/xz-$arch/xztool-v1.2.3" "dist/1.2.3/$arch"
    program "stage/gz-$arch/gztool"
    echo "# $arch" >> "stage/gz-$arch/gztool"
    tar -czf "dist/gztool-1.2.3-$arch.tar.gz" -C "stage/gz-$arch" gztool
    program "stage/xz-$arch/xztool-v1.2.3/xztool"
    tar -cf "stage/xz-$arch.tar" -C "stage/xz-$arch" xztool-v1.2.3
    python3 -c "import lzma, sys; open(sys.argv[2], 'wb').write(lzma.compress(open(sys.argv[1], 'rb').read()))" \
      "stage/xz-$arch.tar" "dist/xztool-v1.2.3.$arch.tar.xz"
    mkdir -p "stage/zip-$arch"
    program "stage/zip-$arch/ziptool"
    echo "# $arch" >> "stage/zip-$arch/ziptool"
    python3 -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1], 'w').write(sys.argv[2], 'ziptool')" \
      "dist/ziptool_$arch.zip" "stage/zip-$arch/ziptool"
    program "dist/1.2.3/$arch/rawtool"
    echo "# $arch" >> "dist/1.2.3/$arch/rawtool"
    # The download is not executable: the install makes it so.
    chmod -x "dist/1.2.3/$arch/rawtool"
  done

  # A git-installed tool: its installer puts a program into PREFIX/bin.
  mkdir lib
  cat > lib/install.sh << 'SH'
#!/bin/sh
mkdir -p "$1/bin"
printf '#!/bin/sh\necho "gittool runs"\n' > "$1/bin/gittool"
chmod +x "$1/bin/gittool"
SH
  chmod +x lib/install.sh
  echo 1111111111111111111111111111111111111111 > lib/HEAD-COMMIT

  cat > tools.json << JSON
{
  "gztool": {
    "version": "1.2.3",
    "url": "file://$PWD/dist/gztool-{v}-{a}.tar.gz",
    "arch": {"amd64": "x86_64", "arm64": "aarch64"},
    "extract": "tar.gz",
    "member": "gztool",
    "sha256": {"amd64": "$(sha dist/gztool-1.2.3-x86_64.tar.gz)", "arm64": "$(sha dist/gztool-1.2.3-aarch64.tar.gz)"}
  },
  "xztool": {
    "version": "1.2.3",
    "url": "file://$PWD/dist/xztool-v{v}.{a}.tar.xz",
    "arch": {"amd64": "x86_64", "arm64": "aarch64"},
    "extract": "tar.xz",
    "member": "xztool-v{v}/xztool",
    "sha256": {"amd64": "$(sha dist/xztool-v1.2.3.x86_64.tar.xz)", "arm64": "$(sha dist/xztool-v1.2.3.aarch64.tar.xz)"}
  },
  "ziptool": {
    "version": "1.2.3",
    "url": "file://$PWD/dist/ziptool_{a}.zip",
    "arch": {"amd64": "x86_64", "arm64": "aarch64"},
    "extract": "zip",
    "member": "ziptool",
    "sha256": {"amd64": "$(sha dist/ziptool_x86_64.zip)", "arm64": "$(sha dist/ziptool_aarch64.zip)"}
  },
  "rawtool": {
    "version": "1.2.3",
    "url": "file://$PWD/dist/{v}/{a}/rawtool",
    "arch": {"amd64": "x86_64", "arm64": "aarch64"},
    "extract": "binary",
    "member": "rawtool",
    "sha256": {"amd64": "$(sha dist/1.2.3/x86_64/rawtool)", "arm64": "$(sha dist/1.2.3/aarch64/rawtool)"}
  },
  "gittool": {
    "version": "v2.0.0",
    "git": "$PWD/lib",
    "extract": "git",
    "commit": "1111111111111111111111111111111111111111",
    "installer": "install.sh",
    "path": "bin"
  }
}
JSON
}

# edit STATEMENT: change the test manifest (m is the parsed JSON).
edit() {
  python3 - "$TOOLS_MANIFEST" "$1" << 'PY'
import json, sys
m = json.load(open(sys.argv[1]))
exec(sys.argv[2])
json.dump(m, open(sys.argv[1], "w"))
PY
}

# on_path TOOL: run TOOL from the directories the script added to GITHUB_PATH.
on_path() { PATH="$(paste -sd: "$GITHUB_PATH"):$PATH" "$1"; }

@test "a tar.gz tool is checked, extracted and put on the PATH" {
  TOOL=gztool run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅ gztool 1.2.3 installed"* ]]
  [ "$(cat "$GITHUB_PATH")" = "$RUNNER_TEMP/gztool" ]
  [ "$(on_path gztool)" = "gztool runs" ]
  # Nothing but the program stays behind.
  [ "$(ls "$RUNNER_TEMP")" = gztool ]
}

@test "a tar.xz tool is taken out of its versioned folder" {
  TOOL=xztool run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(on_path xztool)" = "xztool runs" ]
  [ "$(ls "$RUNNER_TEMP/xztool")" = xztool ]
}

@test "a zip tool is taken out of its archive and made executable" {
  TOOL=ziptool run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅ ziptool 1.2.3 installed"* ]]
  [ "$(on_path ziptool)" = "ziptool runs" ]
  [ "$(ls "$RUNNER_TEMP")" = ziptool ]
}

@test "a binary tool is the download itself, made executable" {
  TOOL=rawtool run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(on_path rawtool)" = "rawtool runs" ]
}

@test "a git tool is cloned at its tag, checked against its commit and installed by its installer" {
  TOOL=gittool run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅ gittool v2.0.0 installed (commit 1111111)"* ]]
  grep -q -- "clone --quiet --depth 1 --branch v2.0.0 $PWD/lib " "$GIT_LOG"
  [ "$(cat "$GITHUB_PATH")" = "$RUNNER_TEMP/gittool/bin" ]
  [ "$(on_path gittool)" = "gittool runs" ]
  # A second install in the same job works too.
  TOOL=gittool run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "arm64 gets its own asset and its own pin" {
  MACHINE=aarch64 TOOL=gztool run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qx '# aarch64' "$RUNNER_TEMP/gztool/gztool"
  MACHINE=arm64 TOOL=rawtool run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qx '# aarch64' "$RUNNER_TEMP/rawtool/rawtool"
}

@test "a download that does not match its pin installs nothing" {
  edit 'm["gztool"]["sha256"]["amd64"] = "0" * 64'
  TOOL=gztool run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::gztool 1.2.3 (x86_64) does not match its pinned SHA-256"* ]]
  [[ "$output" == *"scripts/update-tool-checksums.py"* ]]
  [ ! -e "$RUNNER_TEMP/gztool/gztool" ]
  [ ! -s "$GITHUB_PATH" ]
}

@test "a tag moved off its pinned commit installs nothing" {
  echo 2222222222222222222222222222222222222222 > lib/HEAD-COMMIT
  TOOL=gittool run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::gittool v2.0.0 is not at the pinned commit 1111111111111111111111111111111111111111"* ]]
  [ ! -e "$RUNNER_TEMP/gittool/bin/gittool" ]
  [ ! -s "$GITHUB_PATH" ]
}

@test "fails on an unknown tool, an unusable name or an unsupported architecture" {
  TOOL=nope run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown tool 'nope' (the manifest lists: gittool, gztool, rawtool, xztool, ziptool)"* ]]
  [[ "$output" == *"::error::install-tool cannot install 'nope'"* ]]
  TOOL='../x' run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::unusable tool name '../x'"* ]]
  TOOL='' run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  MACHINE=riscv64 TOOL=gztool run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsupported arch for gztool: riscv64"* ]]
  # A git install needs no architecture.
  MACHINE=riscv64 TOOL=gittool run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "refuses a manifest entry it cannot install safely" {
  edit 'm["gztool"]["extract"] = "rar"'
  TOOL=gztool run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gztool: unsupported extract 'rar'"* ]]
  edit 'm["xztool"]["member"] = "../../xztool"'
  TOOL=xztool run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"leaves its directory"* ]]
  edit 'm["rawtool"]["sha256"]["amd64"] = ""'
  TOOL=rawtool run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"rawtool: no pin for x86_64"* ]]
  [ ! -s "$GITHUB_PATH" ]
}

@test "every entry of the repository's manifest has the shape its extraction needs" {
  run python3 - "$REAL_MANIFEST" << 'PY'
import json, sys
for name, tool in json.load(open(sys.argv[1])).items():
    kind = tool["extract"]
    assert kind in ("tar.gz", "tar.xz", "zip", "binary", "git"), (name, kind)
    if kind == "git":
        assert len(tool["commit"]) == 40 and tool["git"].startswith("https://") and tool["installer"], name
    else:
        assert set(tool["arch"]) == set(tool["sha256"]) == {"amd64", "arm64"}, name
        assert all(len(v) == 64 for v in tool["sha256"].values()), name
        assert tool["url"].startswith("https://") and "{v}" in tool["url"] and tool["member"], name
PY
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}
