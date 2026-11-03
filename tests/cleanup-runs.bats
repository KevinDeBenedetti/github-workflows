#!/usr/bin/env bats
# Tests for .github/actions/cleanup-runs/cleanup-runs.sh

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/cleanup-runs/cleanup-runs.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p bin tmp stub
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  export RUNNER_TEMP="$TMPDIR"
  export STUB_DIR="$BATS_TEST_TMPDIR/stub"
  export GITHUB_TOKEN=secret-token GITHUB_REPOSITORY=o/r GITHUB_API_URL=https://api.github.test
  export DELETE_INTERVAL=0
  unset GITHUB_OUTPUT GITHUB_STEP_SUMMARY GITHUB_SHA KEEP_RUNS OLDER_THAN_DAYS MAX_DELETIONS DRY_RUN
  stub_curl
  workflows 1
}

# refute CMD...: fails the test when CMD succeeds. A bare `! CMD` in the middle
# of a test never fails it: bash's errexit ignores negated commands.
refute() {
  if "$@"; then
    echo "unexpected success: $*" >&2
    return 1
  fi
}

# days_ago N: the UTC date N days ago, the cutoff the script computes.
days_ago() {
  local t=$(($(date -u +%s) - $1 * 86400))
  date -u -d "@$t" +%Y-%m-%d 2> /dev/null || date -u -r "$t" +%Y-%m-%d
}

# workflows ID...: the workflows GitHub lists, their file still there.
workflows() {
  jq -n '{workflows: [$ARGS.positional[] | {id: tonumber, state: "active"}]}' --args "$@" \
    > "$STUB_DIR/workflows-1.json"
}

# old_run ID WORKFLOW CREATED [STATUS] [SHA]: a run the query for old runs
# returns, in the order given (the script must not rely on GitHub's).
old_run() {
  jq -cn --argjson id "$1" --argjson wf "$2" --arg created "$3" \
    --arg status "${4:-completed}" --arg sha "${5:-$(printf '%040d' "$1")}" \
    '{id: $id, workflow_id: $wf, path: ".github/workflows/w\($wf).yml", status: $status,
      created_at: $created, head_sha: $sha}' >> "$STUB_DIR/runs.jsonl"
  jq -s '{workflow_runs: .}' "$STUB_DIR/runs.jsonl" > "$STUB_DIR/runs-1.json"
}

# recent WORKFLOW ID...: the most recent runs of a workflow, newest first.
recent() {
  local wf="$1"
  shift
  jq -n '{workflow_runs: [$ARGS.positional[] | {id: tonumber}]}' --args "$@" > "$STUB_DIR/recent-$wf.json"
}

# open_pull_requests SHA...: the head commits of the open pull requests.
open_pull_requests() {
  jq -n '[$ARGS.positional[] | {head: {sha: .}}]' --args "$@" > "$STUB_DIR/pulls-1.json"
}

# deletions: the runs the script asked GitHub to delete, in order.
deletions() {
  sed -n 's|^DELETE /actions/runs/||p' "$STUB_DIR/curl.log" | paste -sd' ' -
}

# A curl that plays the GitHub API from files in $STUB_DIR:
#   runs-<page>.json       a page of old runs
#   workflows-1.json       the workflows listed
#   recent-<id>.json       the most recent runs of a workflow
#   pulls-1.json           the open pull requests
#   pulls-forbidden        present: listing pull requests answers 403
#   delete-<id>.status     the status a deletion answers (default 204)
# It prints the HTTP status, as `-w '%{http_code}'` does, and logs every call
# as METHOD PATH, the API root of o/r cut off.
stub_curl() {
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
out=/dev/stdout method=GET url=""
printf '%s\n' "$*" >> "$STUB_DIR/curl-args.log"
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -X) method="$2"; shift 2 ;;
    -w) shift 2 ;;
    -H) case "$2" in @*) cat "${2#@}" >> "$STUB_DIR/curl-headers.log" ;; esac; shift 2 ;;
    --retry | --retry-delay | --max-time) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
path="${url#https://api.github.test/repos/o/r}"
printf '%s %s\n' "$method" "$path" >> "$STUB_DIR/curl.log"
reply() { printf '%s' "$2" > "$out"; printf '%s' "$1"; }
page="$(printf '%s' "$path" | sed -n 's/.*[?&]page=\([0-9]*\).*/\1/p')"
case "$method $path" in
  "GET /actions/workflows/"*"/runs?"*)
    id="${path#/actions/workflows/}"
    id="${id%%/*}"
    reply 200 "$(cat "$STUB_DIR/recent-$id.json" 2> /dev/null || echo '{"workflow_runs":[]}')"
    ;;
  "GET /actions/workflows?"*)
    reply 200 "$(cat "$STUB_DIR/workflows-$page.json" 2> /dev/null || echo '{"workflows":[]}')"
    ;;
  "GET /actions/runs?"*)
    reply 200 "$(cat "$STUB_DIR/runs-$page.json" 2> /dev/null || echo '{"workflow_runs":[]}')"
    ;;
  "GET /pulls?"*)
    if [ -f "$STUB_DIR/pulls-forbidden" ]; then
      reply 403 '{"message":"Resource not accessible by integration"}'
    else
      reply 200 "$(cat "$STUB_DIR/pulls-$page.json" 2> /dev/null || echo '[]')"
    fi
    ;;
  "DELETE /actions/runs/"*)
    id="${path#/actions/runs/}"
    if [ -f "$STUB_DIR/delete-$id.status" ]; then
      reply "$(cat "$STUB_DIR/delete-$id.status")" '{"message":"Resource not accessible by integration"}'
    else
      reply 204 ''
    fi
    ;;
  *) reply 404 '{"message":"Not Found"}' ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
}

@test "old runs go oldest first; the KEEP_RUNS most recent of their workflow stay" {
  old_run 103 1 2000-01-03T00:00:00Z
  old_run 101 1 2000-01-01T00:00:00Z
  old_run 102 1 2000-01-02T00:00:00Z
  recent 1 105 104 103
  KEEP_RUNS=3 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(deletions)" = "101 102" ]
  grep -qx 'GET /actions/workflows/1/runs?per_page=3' "$STUB_DIR/curl.log"
  # One page each: a short page ends a listing.
  [ "$(grep -c '^GET /actions/workflows?' "$STUB_DIR/curl.log")" -eq 1 ]
  [[ "$output" == *"Deleted run 101 of 2000-01-01, .github/workflows/w1.yml"* ]]
  [[ "$output" == *"deleted=2"* ]]
  [[ "$output" == *"remaining=0"* ]]
}

@test "a workflow whose file was deleted keeps no old run, and is not asked for its recent runs" {
  printf '{"workflows":[{"id":1,"state":"active"},{"id":8,"state":"deleted"}]}' > "$STUB_DIR/workflows-1.json"
  old_run 201 9 2000-01-01T00:00:00Z
  old_run 202 8 2000-01-02T00:00:00Z
  old_run 203 1 2000-01-03T00:00:00Z
  recent 1 203
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(deletions)" = "201 202" ]
  refute grep -q '/actions/workflows/[89]/' "$STUB_DIR/curl.log"
  [[ "$output" == *"run 201 of 2000-01-01, .github/workflows/w9.yml (workflow file deleted)"* ]]
}

@test "a run not completed, a young run, and the runs of an open pull request or GITHUB_SHA stay" {
  pr_head="$(printf 'a%039d' 1)"
  sha="$(printf 'b%039d' 2)"
  old_run 301 1 2000-01-01T00:00:00Z in_progress
  old_run 302 1 "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  old_run 303 1 2000-01-01T00:00:00Z completed "$pr_head"
  old_run 304 1 2000-01-01T00:00:00Z completed "$sha"
  old_run 305 1 2000-01-01T00:00:00Z
  open_pull_requests "$pr_head"
  GITHUB_SHA="$sha" KEEP_RUNS=0 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(deletions)" = "305" ]
  [[ "$output" == *"and of ${sha:0:7}: 1 to delete"* ]]
}

@test "KEEP_RUNS=0 keeps no run by count and asks for no workflow's recent runs" {
  old_run 351 1 2000-01-01T00:00:00Z
  recent 1 351
  KEEP_RUNS=0 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(deletions)" = "351" ]
  refute grep -q '/actions/workflows/1/runs' "$STUB_DIR/curl.log"
}

@test "the query asks for the completed runs created before the cutoff day; none old, nothing else asked" {
  OLDER_THAN_DAYS=45 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qxF "GET /actions/runs?status=completed&created=%3C$(days_ago 45)&per_page=100&page=1" "$STUB_DIR/curl.log"
  [ "$(wc -l < "$STUB_DIR/curl.log" | tr -d ' ')" -eq 1 ]
  [[ "$output" == *"deleted=0"* ]]
}

@test "a run created on or after the cutoff day stays, whatever the query returned" {
  old_run 401 1 "$(days_ago 29)T12:00:00Z"
  old_run 402 1 "$(days_ago 30)T00:00:00Z"
  old_run 403 1 "$(days_ago 31)T23:59:59Z"
  KEEP_RUNS=0 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(deletions)" = "403" ]
}

@test "a dry run deletes nothing and prints what would go" {
  old_run 501 1 2000-01-01T00:00:00Z
  DRY_RUN=true KEEP_RUNS=0 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  refute grep -q '^DELETE' "$STUB_DIR/curl.log"
  [[ "$output" == *"Dry run: nothing is deleted."* ]]
  [[ "$output" == *"Would delete run 501 of 2000-01-01, .github/workflows/w1.yml"* ]]
  [[ "$output" == *"deleted=1"* ]]
}

@test "MAX_DELETIONS caps a run: the oldest go, the rest is left for the next one" {
  old_run 603 1 2000-01-03T00:00:00Z
  old_run 602 1 2000-01-02T00:00:00Z
  old_run 601 1 2000-01-01T00:00:00Z
  KEEP_RUNS=0 MAX_DELETIONS=2 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(deletions)" = "601 602" ]
  [[ "$output" == *"remaining=1"* ]]
}

@test "a run already gone is fine; any other refusal stops the run with GitHub's answer" {
  old_run 701 1 2000-01-01T00:00:00Z
  old_run 702 1 2000-01-02T00:00:00Z
  old_run 703 1 2000-01-03T00:00:00Z
  echo 404 > "$STUB_DIR/delete-701.status"
  echo 403 > "$STUB_DIR/delete-702.status"
  KEEP_RUNS=0 run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Already gone: run 701"* ]]
  [[ "$output" == *"GitHub answered 403 deleting run 702"*"Resource not accessible by integration"* ]]
  [ "$(deletions)" = "701 702" ]
}

@test "a listing GitHub refuses stops the run before any deletion and names the permissions" {
  old_run 801 1 2000-01-01T00:00:00Z
  touch "$STUB_DIR/pulls-forbidden"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GitHub answered 403 listing /pulls"*"pull-requests: read"* ]]
  refute grep -q '^DELETE' "$STUB_DIR/curl.log"
}

@test "a listing stops after ten pages, and a run listed twice counts once" {
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md"
  jq -n '{workflow_runs: [range(100) | {id: (1000 + .), workflow_id: 9, path: ".github/workflows/gone.yml",
    status: "completed", created_at: "2000-01-01T00:00:00Z", head_sha: "x"}]}' > "$STUB_DIR/page.json"
  for page in 1 2 3 4 5 6 7 8 9 10 11; do
    cp "$STUB_DIR/page.json" "$STUB_DIR/runs-$page.json"
  done
  DRY_RUN=true run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^GET /actions/runs?' "$STUB_DIR/curl.log")" -eq 10 ]
  [[ "$output" == *"deleted=100"* ]]
  grep -q 'GitHub lists 1,000 runs per query at most' "$GITHUB_STEP_SUMMARY"
}

@test "the token travels in a header file, never on curl's command line" {
  old_run 901 1 2000-01-01T00:00:00Z
  KEEP_RUNS=0 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  refute grep -q secret-token "$STUB_DIR/curl-args.log"
  grep -q 'Authorization: Bearer secret-token' "$STUB_DIR/curl-headers.log"
}

@test "the job summary counts the deletions per workflow; outputs also go to GITHUB_OUTPUT" {
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md" GITHUB_OUTPUT="$BATS_TEST_TMPDIR/output"
  old_run 1001 1 2000-01-01T00:00:00Z
  old_run 1002 1 2000-01-02T00:00:00Z
  old_run 1003 9 2000-01-03T00:00:00Z
  KEEP_RUNS=0 MAX_DELETIONS=2 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qxF '| `.github/workflows/w1.yml` | 2 |' "$GITHUB_STEP_SUMMARY"
  grep -qF '**2 deleted**' "$GITHUB_STEP_SUMMARY"
  grep -qF '1 more left for the next run (max-deletions: 2)' "$GITHUB_STEP_SUMMARY"
  grep -qx 'deleted=2' "$GITHUB_OUTPUT"
  grep -qx 'remaining=1' "$GITHUB_OUTPUT"
}

@test "a workflow path is printed with unusual characters replaced" {
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md"
  jq -n '{workflow_runs: [{id: 1101, workflow_id: 9, path: ".github/workflows/::error::x`y|z.yml",
    status: "completed", created_at: "2000-01-01T00:00:00Z", head_sha: "x"}]}' > "$STUB_DIR/runs-1.json"
  DRY_RUN=true run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"run 1101 of 2000-01-01, .github/workflows/__error__x_y_z.yml"* ]]
  refute grep -q '::error::x' <<< "$output"
  grep -qxF '| `.github/workflows/__error__x_y_z.yml` (workflow file deleted) | 1 |' "$GITHUB_STEP_SUMMARY"
}

@test "invalid settings are refused before any request" {
  for setting in KEEP_RUNS=101 KEEP_RUNS=-1 OLDER_THAN_DAYS=0 MAX_DELETIONS=0 MAX_DELETIONS=1001 \
    DELETE_INTERVAL=x DRY_RUN=yes GITHUB_REPOSITORY=o GITHUB_API_URL=http://api.github.test GITHUB_SHA=main; do
    run env "$setting" bash "$SCRIPT"
    [ "$status" -eq 1 ]
  done
  run env -u GITHUB_TOKEN bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [ ! -f "$STUB_DIR/curl.log" ]
}
