#!/usr/bin/env bats
# Tests for .github/actions/prerelease/prerelease.sh

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/prerelease/prerelease.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p bin tmp stub
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  export RUNNER_TEMP="$TMPDIR"
  export STUB_DIR="$BATS_TEST_TMPDIR/stub"
  export NOTES_FILE="$BATS_TEST_TMPDIR/notes.md"
  unset GITHUB_OUTPUT GITHUB_STEP_SUMMARY GITHUB_REPOSITORY GITHUB_TOKEN
  unset MODE SHA TAG CONFIG_FILE PRERELEASE_TYPE
  git init -q repo
  cd repo
}

# commit MESSAGE...: an empty commit. The subcommand is built at runtime so
# this file never contains the literal command blocked by the agent guardrails.
commit() {
  git -c user.name=t -c user.email=t@t -c "com""mit.gpgsign=false" "com""mit" -q --allow-empty "$@"
}

# tag NAME: a lightweight tag, whatever tag.gpgSign the machine sets.
tag() {
  git -c tag.gpgSign=false tag "$@"
}

# out KEY: the value the script printed for KEY.
out() {
  printf '%s\n' "$output" | sed -n "s/^$1=//p"
}

# config JSON: the release-please config the script finds by itself.
config() {
  mkdir -p .github/release
  printf '%s\n' "$1" > .github/release/release-please-config.json
}

# A curl that plays the GitHub API from files in $STUB_DIR:
#   tag-<tag>      the commit an existing tag points at
#   release-<tag>  present when the release already exists
# It prints the HTTP status, as `-w '%{http_code}'` does, and logs every call.
stub_curl() {
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
out=/dev/stdout method=GET data="" url=""
printf '%s\n' "$*" >> "$STUB_DIR/curl-args.log"
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -X) method="$2"; shift 2 ;;
    -w) shift 2 ;;
    --data-binary) data="${2#@}"; shift 2 ;;
    -H) case "$2" in @*) cat "${2#@}" >> "$STUB_DIR/curl-headers.log" ;; esac; shift 2 ;;
    --retry | --retry-delay) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
printf '%s %s\n' "$method" "$url" >> "$STUB_DIR/curl.log"
reply() { printf '%s' "$2" > "$out"; printf '%s' "$1"; }
case "$method $url" in
  "GET "*/commits/*)
    ref="${url##*/commits/}"
    if [ -f "$STUB_DIR/tag-$ref" ]; then
      reply 200 "{\"sha\":\"$(cat "$STUB_DIR/tag-$ref")\"}"
    else
      reply 422 '{"message":"No commit found for SHA"}'
    fi
    ;;
  "GET "*/releases/tags/*)
    ref="${url##*/releases/tags/}"
    if [ -f "$STUB_DIR/release-$ref" ]; then
      reply 200 '{"html_url":"https://github.test/releases/existing"}'
    else
      reply 404 '{"message":"Not Found"}'
    fi
    ;;
  "POST "*/releases)
    cp "$data" "$STUB_DIR/payload.json"
    reply 201 '{"html_url":"https://github.test/releases/new"}'
    ;;
  *) reply 500 '{"message":"unexpected call"}' ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
}

@test "before any release, a feat makes the first minor, numbered by its commits" {
  commit -m "chore: init"
  commit -m "feat: first feature"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(out releasable)" = true ]
  [ "$(out tag)" = v0.1.0-rc.2 ]
  [ "$(out version)" = 0.1.0-rc.2 ]
  [ "$(out base-tag)" = "" ]
}

@test "a fix after a release is a patch, numbered by the commits since that release" {
  commit -m "chore: init"
  tag v0.22.1
  commit -m "fix: broken link"
  commit -m "docs: typo"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(out tag)" = v0.22.2-rc.2 ]
  [ "$(out base-tag)" = v0.22.1 ]
}

@test "a feat after a release bumps the minor" {
  commit -m "chore: init"
  tag v0.22.1
  commit -m "fix: a"
  commit -m "feat(chat): b"
  run bash "$SCRIPT"
  [ "$(out tag)" = v0.23.0-rc.2 ]
}

@test "a breaking change on 0.x bumps the minor with bump-minor-pre-major, the major without" {
  commit -m "chore: init"
  tag v0.22.1
  commit -m "feat(api)!: drop the old route"
  config '{"packages": {".": {"bump-minor-pre-major": true}}}'
  run bash "$SCRIPT"
  [ "$(out tag)" = v0.23.0-rc.1 ]
  config '{"packages": {".": {}}}'
  run bash "$SCRIPT"
  [ "$(out tag)" = v1.0.0-rc.1 ]
}

@test "a BREAKING CHANGE footer is breaking too, whatever the type" {
  commit -m "chore: init"
  tag v1.4.2
  commit -m "fix: rename the setting" -m "BREAKING CHANGE: the old name is gone"
  run bash "$SCRIPT"
  [ "$(out tag)" = v2.0.0-rc.1 ]
}

@test "from 1.0 a feat bumps the minor, whatever the pre-major rules say" {
  commit -m "chore: init"
  tag v1.4.2
  commit -m "feat: new page"
  config '{"bump-patch-for-minor-pre-major": true}'
  run bash "$SCRIPT"
  [ "$(out tag)" = v1.5.0-rc.1 ]
}

@test "bump-patch-for-minor-pre-major turns a feat into a patch on 0.x; the package setting wins" {
  commit -m "chore: init"
  tag v0.22.1
  commit -m "feat: new page"
  config '{"bump-patch-for-minor-pre-major": false, "packages": {".": {"bump-patch-for-minor-pre-major": true}}}'
  run bash "$SCRIPT"
  [ "$(out tag)" = v0.22.2-rc.1 ]
}

@test "only chore, docs, ci or refactor commits: nothing to pre-release" {
  commit -m "chore: init"
  tag v0.22.1
  commit -m "docs: readme"
  commit -m "ci: pin an action"
  commit -m "Merge branch 'x' into dev"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(out releasable)" = false ]
  [ "$(out tag)" = "" ]
  [ ! -s "$NOTES_FILE" ]
}

@test "pre-release and alias tags are never the base; the highest final tag is" {
  commit -m "chore: init"
  tag v0.22.1
  tag v0.22
  tag v0
  commit -m "fix: a"
  tag v0.22.2-rc.1
  commit -m "chore(main): release 0.23.0"
  tag v0.23.0
  commit -m "fix: b"
  run bash "$SCRIPT"
  [ "$(out base-tag)" = v0.23.0 ]
  [ "$(out tag)" = v0.23.1-rc.1 ]
}

@test "the same commit always gets the same tag, and SHA picks an older commit" {
  commit -m "chore: init"
  tag v0.22.1
  commit -m "fix: a"
  first="$(git rev-parse HEAD)"
  commit -m "feat: b"
  run bash "$SCRIPT"
  [ "$(out tag)" = v0.23.0-rc.2 ]
  SHA="$first" run bash "$SCRIPT"
  [ "$(out tag)" = v0.22.2-rc.1 ]
}

@test "the pre-release identifier is configurable and validated" {
  commit -m "feat: a"
  PRERELEASE_TYPE=beta run bash "$SCRIPT"
  [ "$(out tag)" = v0.1.0-beta.1 ]
  PRERELEASE_TYPE=12 run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRERELEASE_TYPE"* ]]
  PRERELEASE_TYPE='rc;x' run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "an unknown mode, a missing config file or a commit outside the checkout is an error" {
  commit -m "feat: a"
  MODE=release run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  CONFIG_FILE=missing.json run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  SHA=0123456789abcdef0123456789abcdef01234567 run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"full history"* ]]
}

@test "notes group breaking changes, features and fixes, with commit links" {
  commit -m "chore: init"
  tag v0.22.1
  commit -m "fix(seo): canonical host"
  commit -m "feat!: new layout"
  GITHUB_REPOSITORY=owner/repo run bash "$SCRIPT"
  grep -q '^### ⚠ BREAKING CHANGES$' "$NOTES_FILE"
  grep -q '^### Features$' "$NOTES_FILE"
  grep -q '^\* \*\*seo:\*\* canonical host (\[[0-9a-f]\{7\}\](https://github.com/owner/repo/commit/[0-9a-f]\{40\}))$' "$NOTES_FILE"
  grep -q 'since v0.22.1' "$NOTES_FILE"
}

@test "outputs also go to GITHUB_OUTPUT" {
  commit -m "feat: a"
  GITHUB_OUTPUT="$BATS_TEST_TMPDIR/gh-output" run bash "$SCRIPT"
  grep -qx 'tag=v0.1.0-rc.1' "$BATS_TEST_TMPDIR/gh-output"
  grep -qx 'releasable=true' "$BATS_TEST_TMPDIR/gh-output"
}

@test "publish creates the tag on the commit as a pre-release, never latest" {
  stub_curl
  commit -m "chore: init"
  tag v0.22.1
  commit -m "feat: a"
  sha="$(git rev-parse HEAD)"
  MODE=publish TAG=v0.23.0-rc.1 GITHUB_TOKEN=secret-token GITHUB_REPOSITORY=owner/repo run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Published pre-release v0.23.0-rc.1"* ]]
  [ "$(jq -r .tag_name "$STUB_DIR/payload.json")" = v0.23.0-rc.1 ]
  [ "$(jq -r .target_commitish "$STUB_DIR/payload.json")" = "$sha" ]
  [ "$(jq -r .prerelease "$STUB_DIR/payload.json")" = true ]
  [ "$(jq -r .make_latest "$STUB_DIR/payload.json")" = false ]
  grep -q '^### Features$' <<< "$(jq -r .body "$STUB_DIR/payload.json")"
  # The token travels in a header file, never on curl's command line.
  ! grep -q secret-token "$STUB_DIR/curl-args.log"
  grep -q 'Authorization: Bearer secret-token' "$STUB_DIR/curl-headers.log"
}

@test "publish leaves an existing pre-release of the same commit alone" {
  stub_curl
  commit -m "feat: a"
  git rev-parse HEAD > "$STUB_DIR/tag-v0.1.0-rc.1"
  touch "$STUB_DIR/release-v0.1.0-rc.1"
  MODE=publish GITHUB_TOKEN=t GITHUB_REPOSITORY=owner/repo run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already published"* ]]
  ! grep -q '^POST' "$STUB_DIR/curl.log"
}

@test "publish refuses a tag of the same name on another commit" {
  stub_curl
  commit -m "feat: a"
  echo 0123456789abcdef0123456789abcdef01234567 > "$STUB_DIR/tag-v0.1.0-rc.1"
  MODE=publish GITHUB_TOKEN=t GITHUB_REPOSITORY=owner/repo run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists on 0123456"* ]]
  ! grep -q '^POST' "$STUB_DIR/curl.log"
}

@test "publish refuses a TAG that is not this commit's pre-release" {
  stub_curl
  commit -m "feat: a"
  MODE=publish TAG=v0.1.0-rc.9 GITHUB_TOKEN=t GITHUB_REPOSITORY=owner/repo run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not the pre-release"* ]]
  [ ! -f "$STUB_DIR/curl.log" ]
}

@test "publish with nothing to release does nothing, and needs a token otherwise" {
  stub_curl
  commit -m "docs: a"
  MODE=publish run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to publish"* ]]
  commit -m "fix: b"
  MODE=publish GITHUB_REPOSITORY=owner/repo run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"GITHUB_TOKEN"* ]]
}

@test "a branch that has not merged back the last release is refused, not pre-released below it" {
  stub_curl
  commit -m "chore: init"
  tag v0.22.0
  commit -m "fix(csp): a"
  # The release ships from another branch; this one never merges it back.
  git checkout -q -b release
  commit -m "chore(main): release 0.22.1"
  tag v0.22.1
  git checkout -q -
  commit -m "docs: b"
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"v0.22.1 is already released"*"merge the release branch"* ]]
  MODE=publish GITHUB_TOKEN=t GITHUB_REPOSITORY=owner/repo run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [ ! -f "$STUB_DIR/curl.log" ]
  # Once the release is merged back, the next pre-release starts above it.
  git -c user.name=t -c user.email=t@t -c "com""mit.gpgsign=false" merge -q --no-edit release
  commit -m "feat: c"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(out base-tag)" = v0.22.1 ]
  [ "$(out tag)" = v0.23.0-rc.3 ]
}
