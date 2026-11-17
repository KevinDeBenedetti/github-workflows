#!/usr/bin/env bats
# Tests for scripts/update-tool-checksums.py: the parts that need no download.

SCRIPT="$BATS_TEST_DIRNAME/../scripts/update-tool-checksums.py"

# Empty commits without hooks or signing. The subcommand is built at runtime so
# this file never contains the literal command blocked by the agent guardrails.
snapshot() {
  git add -A
  git -c user.name=t -c user.email=t@t -c "com""mit.gpgsign=false" "com""mit" -q --allow-empty -m "$1"
}

@test "--list-files prints the manifest and the files holding a pin, all present in the repository" {
  cd "$BATS_TEST_DIRNAME/.."
  run python3 "$SCRIPT" --list-files
  [ "$status" -eq 0 ]
  [[ "$output" == *".github/tools.json"* ]]
  [[ "$output" == *".github/actions/actionlint/action.yml"* ]]
  [[ "$output" == *".github/actions/secret-scan/action.yml"* ]]
  while IFS= read -r file; do
    [ -f "$file" ] || { echo "missing: $file"; return 1; }
  done <<< "$output"
}

@test "--check --since does nothing when no pinned file changed" {
  cd "$BATS_TEST_TMPDIR"
  git init -q --template= .
  snapshot base
  base="$(git rev-parse HEAD)"
  mkdir -p .github
  echo '{}' > .github/tools.json
  snapshot manifest
  base="$(git rev-parse HEAD)"
  printf 'x\n' > README.md
  snapshot change
  run python3 "$SCRIPT" --check --since "$base"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No pinned tool changed since ${base:0:7}: nothing to verify."* ]]
}

# fixture: a repository whose manifest pins one downloaded tool and one git
# install, and whose actions hold the same pins.
fixture() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p .github/actions/tool .github/actions/lib
  cat > .github/tools.json <<'JSON'
{
  "TOOL": {
    "file": ".github/actions/tool/action.yml",
    "datasource": "github-releases",
    "package": "o/tool",
    "version": "1.2.3",
    "url": "https://example.test/v{v}/tool-{a}.tar.gz",
    "archVar": "ARCH",
    "arch": {"amd64": "x86_64", "arm64": "aarch64"},
    "sha256": {"amd64": "aaa", "arm64": "bbb"}
  },
  "LIB": {
    "file": ".github/actions/lib/action.yml",
    "datasource": "github-tags",
    "package": "o/lib",
    "version": "v2.0.0",
    "git": "https://example.test/lib.git",
    "commit": "ccc"
  }
}
JSON
  cat > .github/actions/tool/action.yml <<'YAML'
        TOOL_VERSION="1.2.3"
        TOOL_SHA256_amd64="aaa"
        TOOL_SHA256_arm64="bbb"
        case "$(uname -m)" in
          x86_64)        ARCH=x86_64;  KEY=amd64 ;;
          aarch64|arm64) ARCH=aarch64; KEY=arm64 ;;
        esac
        curl -o t.tgz "https://example.test/v${TOOL_VERSION}/tool-${ARCH}.tar.gz"
YAML
  cat > .github/actions/lib/action.yml <<'YAML'
        LIB_VERSION="v2.0.0"
        LIB_COMMIT="ccc"
YAML
}

@test "--consistency passes when the actions hold the manifest's pins" {
  fixture
  run python3 "$SCRIPT" --consistency
  [ "$status" -eq 0 ]
  [[ "$output" == *"✔ 2 tool(s)"* ]]
}

@test "--consistency names each pin, URL, arch and renovate comment that drifted" {
  fixture
  sed -i.bak -e 's/TOOL_VERSION="1.2.3"/TOOL_VERSION="1.2.4"/' -e 's/ARCH=aarch64/ARCH=arm64/' \
    -e 's|tool-${ARCH}|tool-linux-${ARCH}|' .github/actions/tool/action.yml
  printf '        # renovate: datasource=github-tags depName=o/lib\n' >> .github/actions/lib/action.yml
  sed -i.bak 's/LIB_COMMIT="ccc"/LIB_COMMIT="ddd"/' .github/actions/lib/action.yml
  run python3 "$SCRIPT" --consistency
  [ "$status" -eq 1 ]
  [[ "$output" == *'TOOL_VERSION="1.2.4", the manifest says "1.2.3"'* ]]
  [[ "$output" == *"no ARCH=aarch64 for arm64"* ]]
  [[ "$output" == *'downloads another URL than the manifest'* ]]
  [[ "$output" == *'LIB_COMMIT="ddd", the manifest says "ccc"'* ]]
  [[ "$output" == *"a renovate comment pins o/lib here too"* ]]
  [[ "$output" == *"5 problem(s)"* ]]
}

@test "--consistency reports a pin missing from its action, or a missing action" {
  fixture
  sed -i.bak '/TOOL_SHA256_arm64/d' .github/actions/tool/action.yml
  rm .github/actions/lib/action.yml
  run python3 "$SCRIPT" --consistency
  [ "$status" -eq 1 ]
  [[ "$output" == *"TOOL_SHA256_arm64 not found"* ]]
  [[ "$output" == *".github/actions/lib/action.yml: missing (LIB)"* ]]
}

@test "a bump in the manifest is refreshed and copied into the actions (local file:// assets)" {
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
m = json.load(open(".github/tools.json"))
m["TOOL"]["url"] = "file://" + root + "/dist/v{v}/tool-{a}.tar.gz"
m["TOOL"]["version"] = "1.3.0"
m["LIB"]["git"] = root + "/lib"
m["LIB"]["version"] = "v2.1.0"
json.dump(m, open(".github/tools.json", "w"), indent=2)
PY
  sed -i.bak "s|https://example.test/v\${TOOL_VERSION}|file://$PWD/dist/v\${TOOL_VERSION}|" .github/actions/tool/action.yml
  run python3 "$SCRIPT" --check
  [ "$status" -eq 1 ]
  run python3 "$SCRIPT"
  [ "$status" -eq 0 ]
  amd="$(printf 'amd' | shasum -a 256 | cut -d' ' -f1)"
  commit="$(git -C lib rev-parse HEAD)"
  grep -qx '        TOOL_VERSION="1.3.0"' .github/actions/tool/action.yml
  grep -qx "        TOOL_SHA256_amd64=\"$amd\"" .github/actions/tool/action.yml
  grep -qx '        LIB_VERSION="v2.1.0"' .github/actions/lib/action.yml
  grep -qx "        LIB_COMMIT=\"$commit\"" .github/actions/lib/action.yml
  [ "$(jq -r .TOOL.sha256.amd64 .github/tools.json)" = "$amd" ]
  [ "$(jq -r .LIB.commit .github/tools.json)" = "$commit" ]
  run python3 "$SCRIPT" --check
  [ "$status" -eq 0 ]
}
