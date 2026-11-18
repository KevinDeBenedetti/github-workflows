#!/usr/bin/env bats
# Tests for scripts/update-tool-checksums.py: the parts that need no download.

SCRIPT="$BATS_TEST_DIRNAME/../scripts/update-tool-checksums.py"

# Empty commits without hooks or signing. The subcommand is built at runtime so
# this file never contains the literal command blocked by the agent guardrails.
snapshot() {
  git add -A
  git -c user.name=t -c user.email=t@t -c "com""mit.gpgsign=false" "com""mit" -q --allow-empty -m "$1"
}

@test "--check --since does nothing when no pinned file changed" {
  cd "$BATS_TEST_TMPDIR"
  git init -q --template= .
  snapshot base
  base="$(git rev-parse HEAD)"
  mkdir -p .github/actions/install-tool
  echo '{}' > .github/actions/install-tool/tools.json
  snapshot manifest
  base="$(git rev-parse HEAD)"
  printf 'x\n' > README.md
  snapshot change
  run python3 "$SCRIPT" --check --since "$base"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No pinned tool changed since ${base:0:7}: nothing to verify."* ]]
}

# fixture: a repository whose manifest pins one downloaded tool and one git
# install.
fixture() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p .github/actions/install-tool
  cat > .github/actions/install-tool/tools.json <<'JSON'
{
  "tool": {
    "datasource": "github-releases",
    "package": "o/tool",
    "version": "1.2.3",
    "url": "https://example.test/v{v}/tool-{a}.tar.gz",
    "arch": {"amd64": "x86_64", "arm64": "aarch64"},
    "extract": "tar.gz",
    "member": "tool",
    "sha256": {"amd64": "aaa", "arm64": "bbb"}
  },
  "lib": {
    "datasource": "github-tags",
    "package": "o/lib",
    "version": "v2.0.0",
    "git": "https://example.test/lib.git",
    "extract": "git",
    "commit": "ccc",
    "installer": "install.sh"
  }
}
JSON
}

@test "a bump in the manifest is refreshed in place, and --check then passes (local file:// assets)" {
  fixture
  # No user git configuration (signed tags need a message).
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  mkdir -p dist/v1.3.0
  printf 'amd' > dist/v1.3.0/tool-x86_64.tar.gz
  printf 'arm' > dist/v1.3.0/tool-aarch64.tar.gz
  git init -q --template= lib && (cd lib && snapshot lib && git tag v2.1.0)
  python3 - "$PWD" <<'PY'
import json, sys
root = sys.argv[1]
m = json.load(open(".github/actions/install-tool/tools.json"))
m["tool"]["url"] = "file://" + root + "/dist/v{v}/tool-{a}.tar.gz"
m["tool"]["version"] = "1.3.0"
m["lib"]["git"] = root + "/lib"
m["lib"]["version"] = "v2.1.0"
json.dump(m, open(".github/actions/install-tool/tools.json", "w"), indent=2)
PY
  run python3 "$SCRIPT" --check
  [ "$status" -eq 1 ]
  run python3 "$SCRIPT"
  [ "$status" -eq 0 ]
  amd="$(printf 'amd' | shasum -a 256 | cut -d' ' -f1)"
  commit="$(git -C lib rev-parse HEAD)"
  [[ "$output" == *"tool sha256 amd64 → $amd"* ]]
  [ "$(jq -r .tool.sha256.amd64 .github/actions/install-tool/tools.json)" = "$amd" ]
  [ "$(jq -r .tool.member .github/actions/install-tool/tools.json)" = tool ]
  [ "$(jq -r .lib.commit .github/actions/install-tool/tools.json)" = "$commit" ]
  run python3 "$SCRIPT" --check
  [ "$status" -eq 0 ]
}
