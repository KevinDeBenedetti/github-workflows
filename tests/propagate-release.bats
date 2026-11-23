#!/usr/bin/env bats
# Tests for .github/actions/propagate-release/: bump-pins.py (which pins move)
# and propagate-release.sh (the pull request of each consumer repository).

ACTION="$BATS_TEST_DIRNAME/../.github/actions/propagate-release"
SCRIPT="$ACTION/propagate-release.sh"
BUMP="$ACTION/bump-pins.py"

load helpers/fake-github
SHA=1111111111111111111111111111111111111111
OLD=2222222222222222222222222222222222222222

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p bin tmp stub/sent
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  export RUNNER_TEMP="$TMPDIR"
  export STUB_DIR="$BATS_TEST_TMPDIR/stub"
  export SOURCE=o/src TAG=v1.1.0 GITHUB_TOKEN=app-token SOURCE_TOKEN=source-token
  export GITHUB_API_URL=https://api.github.test GITHUB_GRAPHQL_URL=https://api.github.test/graphql
  export GITHUB_SERVER_URL=https://github.test
  unset GITHUB_STEP_SUMMARY GITHUB_REPOSITORY REPOSITORIES AUTO_MERGE DRY_RUN
  stub_curl
}

# refute CMD...: fails the test when CMD succeeds (a bare `! CMD` in the
# middle of a test never fails it).
refute() {
  if "$@"; then
    echo "unexpected success: $*" >&2
    return 1
  fi
}

# pins FILE: runs bump-pins.py for o/src v1.1.0 on FILE.
pins() {
  run python3 "$BUMP" o/src v1.1.0 "$SHA" "$1"
}

# consumer NAME [BRANCH] [JSON]: a repository of o whose BRANCH (default main)
# holds the files written under files-NAME/ (call `file` first), with JSON
# merged into its metadata.
consumer() {
  local name="$1" branch="${2:-main}" extra="${3:-{\}}" path sha
  jq -n --arg b "$branch" --argjson extra "$extra" \
    '{default_branch: $b, archived: false} + $extra' > "$STUB_DIR/repo-$name.json"
  printf '{"object":{"sha":"%s"}}' "$(printf 'base-%s' "$name" | git hash-object --stdin)" \
    > "$STUB_DIR/ref-$name-${branch//\//_}.json"
  echo '[]' > "$STUB_DIR/tree-entries"
  while IFS= read -r path; do
    sha="$(git hash-object "$STUB_DIR/files-$name/$path")"
    cp "$STUB_DIR/files-$name/$path" "$STUB_DIR/blob-$sha"
    jq --arg p "$path" --arg s "$sha" '. + [{path: $p, mode: "100644", type: "blob", sha: $s}]' \
      "$STUB_DIR/tree-entries" > "$STUB_DIR/tree-entries.next"
    mv "$STUB_DIR/tree-entries.next" "$STUB_DIR/tree-entries"
  done < <(cd "$STUB_DIR/files-$name" && find . -type f | sed 's|^\./||' | sort)
  jq -n --slurpfile t "$STUB_DIR/tree-entries" '{sha: "basetree", truncated: false, tree: $t[0]}' \
    > "$STUB_DIR/tree-$name.json"
}

# file NAME PATH CONTENT: a file of repository NAME.
file() {
  mkdir -p "$(dirname "$STUB_DIR/files-$1/$2")"
  printf '%s\n' "$3" > "$STUB_DIR/files-$1/$2"
}

# sent 'METHOD PATH': the last payload sent to that endpoint.
sent() {
  local seq
  seq="$(grep -nxF "$1" "$STUB_DIR/curl.log" | tail -n 1 | cut -d: -f1)"
  cat "$STUB_DIR/sent/$seq.json"
}

# writes: the requests that change something, in order.
writes() {
  grep -v '^GET ' "$STUB_DIR/curl.log"
}

# A curl that plays the GitHub API from files in $STUB_DIR, and logs every
# call as "METHOD PATH" (API root cut off), with its payload in sent/N.json
# and the headers it got in curl-headers.log (helpers/fake-github.bash).
# Besides the files
# `consumer` writes:
#   rules-<name>.json     the rules of the target branch (default: 404)
#   pulls-<name>.json     the open pull requests (default: none)
#   automerge-on-<name>   present: the pull request already has auto-merge
#   graphql-error         the error that turning auto-merge on answers
stub_curl() {
  fake_github https://api.github.test "$(cat <<'EOF'
case "$method $path" in
  "GET /repos/o/src/releases/latest") reply 200 '{"tag_name":"v1.1.0"}' ;;
  "GET /repos/o/src/commits/"*) reply 200 '{"sha":"1111111111111111111111111111111111111111"}' ;;
  "GET /repos/o/"*/git/ref/heads/*)
    name="${path#/repos/o/}"; name="${name%%/*}"; ref="${path#*/git/ref/heads/}"
    reply_file "ref-$name-${ref//\//_}.json" 200 ;;
  "GET /repos/o/"*/git/trees/*) name="${path#/repos/o/}"; reply_file "tree-${name%%/*}.json" 200 ;;
  "GET /repos/o/"*/git/blobs/*) reply_file "blob-${path##*/}" 200 ;;
  "GET /repos/o/"*/git/commits/*) reply_file "commit-${path##*/}.json" 200 ;;
  "GET /repos/o/"*/rules/branches/*) name="${path#/repos/o/}"; reply_file "rules-${name%%/*}.json" 200 ;;
  "GET /repos/o/"*/pulls\?*) name="${path#/repos/o/}"; name="${name%%/*}"
    if [ -f "$STUB_DIR/pulls-$name.json" ]; then reply 200 "$(cat "$STUB_DIR/pulls-$name.json")"; else reply 200 '[]'; fi ;;
  "GET /repos/o/"*) reply_file "repo-${path#/repos/o/}.json" 200 ;;
  "POST /repos/o/"*/git/blobs) reply 201 "{\"sha\":\"$(git hash-object "$data")\"}" ;;
  "POST /repos/o/"*/git/trees) reply 201 '{"sha":"newtree"}' ;;
  "POST /repos/o/"*/git/commits) reply 201 '{"sha":"newcommit"}' ;;
  "POST /repos/o/"*/git/refs) reply 201 '{}' ;;
  "PATCH /repos/o/"*/git/refs/heads/*) reply 200 '{}' ;;
  "POST /repos/o/"*/pulls | "PATCH /repos/o/"*/pulls/*)
    name="${path#/repos/o/}"; name="${name%%/*}"; auto=null
    [ ! -f "$STUB_DIR/automerge-on-$name" ] || auto='{"merge_method":"squash"}'
    status=201; [ "$method" = POST ] || status=200
    reply "$status" "{\"number\":7,\"html_url\":\"https://github.test/o/$name/pull/7\",\"node_id\":\"PR_$name\",\"auto_merge\":$auto}" ;;
  "POST /graphql")
    if [ -f "$STUB_DIR/graphql-error" ]; then
      reply 200 "$(jq -n --rawfile m "$STUB_DIR/graphql-error" '{errors: [{message: ($m | rtrimstr("\n"))}]}')"
    else
      reply 200 '{"data":{"enablePullRequestAutoMerge":{"clientMutationId":null}}}'
    fi ;;
esac
EOF
)"
}

# ── Which pins move (bump-pins.py) ───────────────────────────────────────────

@test "a SHA pin with a version comment moves to the release, its comment kept in style" {
  printf '%s\n' \
    "    uses: o/src/.github/workflows/ci.yml@$OLD # v1.0.0" \
    "    uses: \"o/src/.github/workflows/ci.yml@$OLD\" # 1.0.0" \
    "    uses: O/SRC/.github/actions/setup@$OLD #v1.0.0-rc.1" > w.yml
  pins w.yml
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p w.yml)" = "    uses: o/src/.github/workflows/ci.yml@$SHA # v1.1.0" ]
  [ "$(sed -n 2p w.yml)" = "    uses: \"o/src/.github/workflows/ci.yml@$SHA\" # 1.1.0" ]
  [ "$(sed -n 3p w.yml)" = "    uses: O/SRC/.github/actions/setup@$SHA #v1.1.0" ]
  [ "$(printf '%s\n' "$output" | sed -n 1p)" = "$(printf 'w.yml\t.github/workflows/ci.yml\tv1.0.0\tv1.1.0')" ]
}

@test "a version tag pin moves to the release; the comment after it is kept" {
  echo "  - uses: o/src/.github/actions/setup@v1.0.0 # x-release-please-version" > w.yml
  pins w.yml
  [ "$status" -eq 0 ]
  [ "$(cat w.yml)" = "  - uses: o/src/.github/actions/setup@v1.1.0 # x-release-please-version" ]
}

@test "moving refs, an unlabelled SHA, a newer pin and another repository stay" {
  printf '%s\n' \
    "uses: o/src/.github/workflows/a.yml@main" \
    "uses: o/src/.github/workflows/a.yml@v1" \
    "uses: o/src/.github/workflows/a.yml@v1.0" \
    "uses: o/src/.github/workflows/a.yml@$OLD" \
    "uses: o/src/.github/workflows/a.yml@$OLD # main" \
    "uses: o/src/.github/workflows/a.yml@v1.1.0" \
    "uses: o/src/.github/workflows/a.yml@v1.2.0" \
    "uses: o/src/.github/workflows/a.yml@$OLD # v2.0.0" \
    "uses: o/src2/.github/workflows/a.yml@v1.0.0" \
    "uses: x/src/.github/workflows/a.yml@v1.0.0" > w.yml
  cp w.yml before.yml
  pins w.yml
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  cmp w.yml before.yml
}

@test "a pre-release of the release moves; CRLF line ends and other lines are kept byte for byte" {
  printf 'name: x\r\n  uses: o/src/.github/workflows/a.yml@v1.1.0-rc.2\r\n# caf\xc3\xa9 \xff\r\n' > w.yml
  pins w.yml
  [ "$status" -eq 0 ]
  printf 'name: x\r\n  uses: o/src/.github/workflows/a.yml@v1.1.0\r\n# caf\xc3\xa9 \xff\r\n' > expected.yml
  cmp w.yml expected.yml
}

@test "the prek.toml rev of the source's hooks moves to the release; other repositories and moving revs stay" {
  cat > prek.toml <<'EOF'
[[repos]]
repo = "https://github.com/O/src"
# Same release as the workflows.

rev = "v1.0.0"
hooks = [{ id = "check" }]

[[repos]]
repo = "https://github.com/o/src2"
rev = "v1.0.0"

[[repos]]
repo = 'https://github.com/o/src.git'
rev = '1.0.0'

[[repos]]
repo = "https://github.com/o/src"
rev = "main"
EOF
  pins prek.toml
  [ "$status" -eq 0 ]
  [ "$(sed -n 5p prek.toml)" = 'rev = "v1.1.0"' ]
  [ "$(sed -n 10p prek.toml)" = 'rev = "v1.0.0"' ]
  [ "$(sed -n 14p prek.toml)" = "rev = '1.1.0'" ]
  [ "$(sed -n 18p prek.toml)" = 'rev = "main"' ]
  [ "$(printf '%s\n' "$output" | sed -n 1p)" = "$(printf 'prek.toml\t.pre-commit-hooks.yaml\tv1.0.0\tv1.1.0')" ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "bump-pins.py refuses a bad source, tag or commit" {
  echo x > w.yml
  run python3 "$BUMP" o v1.1.0 "$SHA" w.yml
  [ "$status" -eq 2 ]
  run python3 "$BUMP" o/src 1.1.0 "$SHA" w.yml
  [ "$status" -eq 2 ]
  run python3 "$BUMP" o/src v1.1.0 abc w.yml
  [ "$status" -eq 2 ]
}

# ── The pull requests (propagate-release.sh) ─────────────────────────────────

@test "a repository with an old pin gets one commit, a pull request and auto-merge" {
  file app .github/workflows/ci.yml "    uses: o/src/.github/workflows/ci.yml@$OLD # v1.0.0"
  file app .github/workflows/other.yml "    uses: actions/checkout@v7"
  consumer app
  REPOSITORIES=app run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(writes)" = "$(printf '%s\n' 'POST /repos/o/app/git/blobs' 'POST /repos/o/app/git/trees' \
    'POST /repos/o/app/git/commits' 'POST /repos/o/app/git/refs' 'POST /repos/o/app/pulls' 'POST /graphql')" ]
  # The new content, the tree on top of the branch's, its file mode kept.
  [ "$(sent 'POST /repos/o/app/git/blobs' | jq -r .content | base64 --decode)" = \
    "    uses: o/src/.github/workflows/ci.yml@$SHA # v1.1.0" ]
  sent 'POST /repos/o/app/git/trees' | jq -e '.base_tree == "basetree" and (.tree | length) == 1
    and .tree[0].path == ".github/workflows/ci.yml" and .tree[0].mode == "100644"'
  sent 'POST /repos/o/app/git/commits' | jq -e --arg p "$(jq -r .object.sha "$STUB_DIR/ref-app-main.json")" \
    '.tree == "newtree" and .parents == [$p] and (.message | startswith("ci(deps): bump o/src to v1.1.0\n\n"))'
  sent 'POST /repos/o/app/git/refs' | jq -e '.ref == "refs/heads/bump/src" and .sha == "newcommit"'
  sent 'POST /repos/o/app/pulls' | jq -e '.head == "bump/src" and .base == "main" and .title == "ci(deps): bump o/src to v1.1.0"
    and (.body | contains("| `.github/workflows/ci.yml` | `.github/workflows/ci.yml` | v1.0.0 | v1.1.0 |"))'
  sent 'POST /graphql' | jq -e '.variables == {id: "PR_app", method: "SQUASH"}'
  # Files are read raw, blob by blob.
  grep -q '^Accept: application/vnd.github.raw$' "$STUB_DIR/curl-headers.log"
  [[ "$output" == *"o/app: pull request, merges once its checks pass https://github.test/o/app/pull/7"* ]]
}

@test "a root prek.toml is read too: its hook rev moves in the same commit as the workflows" {
  file app .github/workflows/ci.yml "    uses: o/src/.github/workflows/ci.yml@v1.0.0"
  file app prek.toml "$(printf '[[repos]]\nrepo = "https://github.com/o/src"\nrev = "v1.0.0"')"
  file app docs/prek.toml "$(printf '[[repos]]\nrepo = "https://github.com/o/src"\nrev = "v1.0.0"')"
  consumer app
  REPOSITORIES=app run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  sent 'POST /repos/o/app/git/trees' | jq -e '[.tree[].path] | sort == [".github/workflows/ci.yml", "prek.toml"]'
  # Every blob sent, decoded: the prek.toml one carries the new rev.
  for f in "$STUB_DIR"/sent/*.json; do jq -r '.content // empty' "$f"; done | base64 --decode > blobs
  grep -qx 'rev = "v1.1.0"' blobs
  sent 'POST /repos/o/app/pulls' | jq -e '.body | contains("| `prek.toml` | `.pre-commit-hooks.yaml` | v1.0.0 | v1.1.0 |")'
}

@test "the next release updates the open pull request and force-moves its branch" {
  file app .github/workflows/ci.yml "    uses: o/src/.github/workflows/ci.yml@$OLD # v1.0.0"
  consumer app
  echo '{"object":{"sha":"oldbump"}}' > "$STUB_DIR/ref-app-bump_src.json"
  echo '{"tree":{"sha":"othertree"},"parents":[{"sha":"x"}]}' > "$STUB_DIR/commit-oldbump.json"
  echo '[{"number":7}]' > "$STUB_DIR/pulls-app.json"
  touch "$STUB_DIR/automerge-on-app"
  REPOSITORIES=app run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  sent 'PATCH /repos/o/app/git/refs/heads/bump/src' | jq -e '. == {sha: "newcommit", force: true}'
  sent 'PATCH /repos/o/app/pulls/7' | jq -e '.title == "ci(deps): bump o/src to v1.1.0"'
  refute grep -q 'POST /repos/o/app/pulls$' "$STUB_DIR/curl.log"
  # Auto-merge already on: not asked again.
  refute grep -q 'POST /graphql' "$STUB_DIR/curl.log"
}

@test "a branch that already holds the change on the same base is left as it is" {
  file app .github/workflows/ci.yml "    uses: o/src/.github/workflows/ci.yml@$OLD # v1.0.0"
  consumer app
  base="$(jq -r .object.sha "$STUB_DIR/ref-app-main.json")"
  echo '{"object":{"sha":"samebump"}}' > "$STUB_DIR/ref-app-bump_src.json"
  printf '{"tree":{"sha":"newtree"},"parents":[{"sha":"%s"}]}' "$base" > "$STUB_DIR/commit-samebump.json"
  echo '[{"number":7}]' > "$STUB_DIR/pulls-app.json"
  REPOSITORIES=app run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  refute grep -qE 'POST /repos/o/app/git/commits|/git/refs' <(writes)
}

@test "a repository with nothing to move is not written to" {
  file app .github/workflows/ci.yml "    uses: o/src/.github/workflows/ci.yml@v1.1.0"
  consumer app
  REPOSITORIES=app run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$(writes)" ]
  [[ "$output" == *"o/app: nothing to move"* ]]
}

@test "a dry run reads, prints the moves, and writes nothing" {
  file app .github/workflows/ci.yml "    uses: o/src/.github/workflows/ci.yml@$OLD # v1.0.0"
  consumer app
  DRY_RUN=true REPOSITORIES=app run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$(writes)" ]
  [[ "$output" == *".github/workflows/ci.yml: .github/workflows/ci.yml v1.0.0 -> v1.1.0"* ]]
  [[ "$output" == *"o/app: would move 1 pin(s) in 1 file(s)"* ]]
}

@test "name:branch targets that branch; an archived repository is skipped" {
  file app .github/workflows/ci.yml "    uses: o/src/.github/workflows/ci.yml@$OLD # v1.0.0"
  consumer app dev '{"default_branch": "main"}'
  file old .github/workflows/ci.yml "    uses: o/src/.github/workflows/ci.yml@$OLD # v1.0.0"
  consumer old main '{"archived": true}'
  REPOSITORIES=$'app:dev\nold' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q 'GET /repos/o/app/git/ref/heads/dev$' "$STUB_DIR/curl.log"
  sent 'POST /repos/o/app/pulls' | jq -e '.base == "dev"'
  [[ "$output" == *"o/old: skipped: archived"* ]]
  refute grep -q '/repos/o/old/git/' "$STUB_DIR/curl.log"
}

@test "a repository the App cannot reach fails, the others still get their pull request" {
  file app .github/workflows/ci.yml "    uses: o/src/.github/workflows/ci.yml@$OLD # v1.0.0"
  consumer app
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md"
  REPOSITORIES='ghost, app' run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::o/ghost: not reachable (GitHub answered 404): install the GitHub App on it"* ]]
  grep -q 'POST /repos/o/app/pulls' "$STUB_DIR/curl.log"
  grep -qF '| `o/ghost` | failed: not reachable' "$GITHUB_STEP_SUMMARY"
  grep -qF '| `o/app` | pull request, merges once its checks pass — https://github.test/o/app/pull/7 |' "$GITHUB_STEP_SUMMARY"
}

@test "an unexpected failure inside a repository is caught and reported, not skipped silently" {
  file app .github/workflows/ci.yml "    uses: o/src/.github/workflows/ci.yml@$OLD # v1.0.0"
  consumer app
  printf '#!/usr/bin/env bash\nexit 3\n' > bin/python3
  chmod +x bin/python3
  REPOSITORIES=app run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"o/app: failed: unexpected error, see the log"* ]]
  refute grep -q 'nothing to move' <<< "$output"
  [ -z "$(writes)" ]
}

@test "a repository without auto-merge, or with no required check, keeps the pull request for a person, with a notice" {
  file app .github/workflows/ci.yml "    uses: o/src/.github/workflows/ci.yml@$OLD # v1.0.0"
  consumer app main '{"allow_squash_merge": false, "allow_merge_commit": true}'
  echo 'Auto merge is not allowed for this repository' > "$STUB_DIR/graphql-error"
  REPOSITORIES=app run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  sent 'POST /graphql' | jq -e '.variables.method == "MERGE"'
  [[ "$output" == *"::notice::o/app: no auto-merge (Auto merge is not allowed for this repository): the pull request waits for a person."* ]]
  [[ "$output" == *"o/app: pull request, to merge by hand"* ]]
  refute grep -q '::warning::' <<< "$output"
  echo 'Pull request Pull request is in clean status' > "$STUB_DIR/graphql-error"
  REPOSITORIES=app run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::notice::o/app: no auto-merge (Pull request Pull request is in clean status)"* ]]
}

@test "an unexpected auto-merge error is a warning, and the run still succeeds" {
  file app .github/workflows/ci.yml "    uses: o/src/.github/workflows/ci.yml@$OLD # v1.0.0"
  consumer app
  echo 'Something went wrong' > "$STUB_DIR/graphql-error"
  REPOSITORIES=app run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::o/app: auto-merge not turned on (Something went wrong)"* ]]
}

@test "the merge method is one the branch's rules allow too" {
  file app .github/workflows/ci.yml "    uses: o/src/.github/workflows/ci.yml@$OLD # v1.0.0"
  consumer app
  # The repository allows every method; its ruleset, rebase only.
  echo '[{"type":"deletion"},{"type":"pull_request","parameters":{"allowed_merge_methods":["rebase"]}}]' \
    > "$STUB_DIR/rules-app.json"
  REPOSITORIES=app run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q 'GET /repos/o/app/rules/branches/main$' "$STUB_DIR/curl.log"
  sent 'POST /graphql' | jq -e '.variables.method == "REBASE"'
}

@test "without a tag, the latest release of the source is used" {
  file app .github/workflows/ci.yml "    uses: o/src/.github/workflows/ci.yml@$OLD # v1.0.0"
  consumer app
  TAG='' DRY_RUN=true REPOSITORIES=app run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q 'GET /repos/o/src/releases/latest' "$STUB_DIR/curl.log"
  [[ "$output" == *"Moving the pins of o/src to v1.1.0 (1111111)."* ]]
}

@test "each token travels in a header file, never on curl's command line" {
  file app .github/workflows/ci.yml "    uses: o/src/.github/workflows/ci.yml@$OLD # v1.0.0"
  consumer app
  REPOSITORIES=app run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  refute grep -qE 'app-token|source-token' "$STUB_DIR/curl-args.log"
  grep -q 'Authorization: Bearer app-token' "$STUB_DIR/curl-headers.log"
  grep -q 'Authorization: Bearer source-token' "$STUB_DIR/curl-headers.log"
}

@test "invalid settings are refused before any request" {
  for setting in 'REPOSITORIES=o/app' 'REPOSITORIES=app:bad branch' 'REPOSITORIES= , ' 'TAG=1.1.0' \
    'AUTO_MERGE=yes' 'DRY_RUN=1' 'SOURCE=src' 'GITHUB_API_URL=http://api.github.test'; do
    run env REPOSITORIES=app "$setting" bash "$SCRIPT"
    [ "$status" -eq 1 ]
  done
  run env -u GITHUB_TOKEN REPOSITORIES=app bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [ ! -f "$STUB_DIR/curl.log" ]
}
