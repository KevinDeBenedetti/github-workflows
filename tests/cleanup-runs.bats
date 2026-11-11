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
  unset GITHUB_OUTPUT GITHUB_STEP_SUMMARY GITHUB_SHA KEEP_RUNS OLDER_THAN_DAYS MAX_DELETIONS DRY_RUN \
    ARTIFACTS_OLDER_THAN_DAYS
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

# artifact ID RUN CREATED [SIZE] [EXPIRED] [NAME]: an artifact GitHub lists, in
# the order given; 1 MB, not expired and named report-ID by default.
artifact() {
  jq -cn --argjson id "$1" --argjson run "$2" --arg created "$3" --argjson size "${4:-1048576}" \
    --argjson expired "${5:-false}" --arg name "${6:-report-$1}" \
    '{id: $id, name: $name, size_in_bytes: $size, created_at: $created, expired: $expired,
      workflow_run: {id: $run}}' >> "$STUB_DIR/artifacts.jsonl"
  jq -s '{total_count: length, artifacts: .}' "$STUB_DIR/artifacts.jsonl" > "$STUB_DIR/artifacts-1.json"
}

# runs_in_state STATE ID...: the runs GitHub lists with that status.
runs_in_state() {
  local state="$1"
  shift
  jq -n '{workflow_runs: [$ARGS.positional[] | {id: tonumber}]}' --args "$@" > "$STUB_DIR/runs-$state.json"
}

# artifact_deletions: the artifacts the script asked GitHub to delete, in order.
artifact_deletions() {
  sed -n 's|^DELETE /actions/artifacts/||p' "$STUB_DIR/curl.log" | paste -sd' ' -
}

# stub_sleep: a sleep that only logs the seconds it was asked to wait.
stub_sleep() {
  cat > "$BATS_TEST_TMPDIR/bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$STUB_DIR/sleep.log"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/sleep"
}

# A curl that plays the GitHub API from files in $STUB_DIR:
#   runs-<page>.json       a page of old runs (status=completed)
#   runs-<state>.json      the runs listed with another status (one page)
#   workflows-1.json       the workflows listed
#   recent-<id>.json       the most recent runs of a workflow
#   pulls-1.json           the open pull requests
#   pulls-forbidden        present: listing pull requests answers 403
#   artifacts-<page>.json  a page of artifacts
#   delete-<id>.status     the status deleting run <id> answers (default 204)
#   delete-artifact-<id>.status  the same for artifact <id>
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
  "GET /actions/runs?status=completed&"*)
    reply 200 "$(cat "$STUB_DIR/runs-$page.json" 2> /dev/null || echo '{"workflow_runs":[]}')"
    ;;
  "GET /actions/runs?status="*)
    state="${path#/actions/runs?status=}"
    state="${state%%&*}"
    if [ "$page" = 1 ] && [ -f "$STUB_DIR/runs-$state.json" ]; then
      reply 200 "$(cat "$STUB_DIR/runs-$state.json")"
    else
      reply 200 '{"workflow_runs":[]}'
    fi
    ;;
  "GET /actions/artifacts?"*)
    reply 200 "$(cat "$STUB_DIR/artifacts-$page.json" 2> /dev/null || echo '{"artifacts":[]}')"
    ;;
  "DELETE /actions/artifacts/"*)
    id="${path#/actions/artifacts/}"
    if [ -f "$STUB_DIR/delete-artifact-$id.status" ]; then
      reply "$(cat "$STUB_DIR/delete-artifact-$id.status")" '{"message":"Resource not accessible by integration"}'
    else
      reply 204 ''
    fi
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

@test "by default no artifact is listed nor deleted on its own, and the artifact outputs say 0" {
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md"
  old_run 1201 1 2000-01-01T00:00:00Z
  artifact 2201 1201 2000-01-01T00:00:00Z
  for value in unset 0 000; do
    : > "$STUB_DIR/curl.log"
    : > "$GITHUB_STEP_SUMMARY"
    if [ "$value" = unset ]; then
      KEEP_RUNS=0 run bash "$SCRIPT"
    else
      KEEP_RUNS=0 ARTIFACTS_OLDER_THAN_DAYS="$value" run bash "$SCRIPT"
    fi
    [ "$status" -eq 0 ]
    refute grep -q '/actions/artifacts' "$STUB_DIR/curl.log"
    refute grep -q 'status=queued' "$STUB_DIR/curl.log"
    [ "$(deletions)" = "1201" ]
    grep -qx 'artifacts-deleted=0' <<< "$output"
    grep -qx 'artifacts-bytes-freed=0' <<< "$output"
    [[ "$output" == *": 1 to delete, at most 500 in this run."* ]]
    refute grep -q 'Artifacts' "$GITHUB_STEP_SUMMARY"
  done
}

@test "old artifacts go on their own, the kept runs' included; the runs and the young artifacts stay" {
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md" GITHUB_OUTPUT="$BATS_TEST_TMPDIR/output"
  pr_head="$(printf 'a%039d' 1)"
  sha="$(printf 'b%039d' 2)"
  # Old runs the run rules keep: the most recent of its workflow, the head of
  # an open pull request, GITHUB_SHA.
  old_run 1301 1 2000-01-01T00:00:00Z
  old_run 1302 1 2000-01-02T00:00:00Z completed "$pr_head"
  old_run 1303 1 2000-01-03T00:00:00Z completed "$sha"
  recent 1 1301
  open_pull_requests "$pr_head"
  artifact 2303 1303 2000-01-03T00:00:00Z
  artifact 2301 1301 2000-01-01T00:00:00Z
  artifact 2302 1302 2000-01-02T00:00:00Z
  # Run 1304 is younger than OLDER_THAN_DAYS: its artifacts go once created
  # before their own cutoff day.
  artifact 2304 1304 "$(days_ago 4)T23:59:59Z"
  artifact 2305 1304 "$(days_ago 3)T00:00:00Z"
  GITHUB_SHA="$sha" KEEP_RUNS=1 ARTIFACTS_OLDER_THAN_DAYS=3 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(deletions)" = "" ]
  [ "$(artifact_deletions)" = "2301 2302 2303 2304" ]
  [[ "$output" == *"Artifacts created before $(days_ago 3) (3 days) of any completed run: 4 to delete."* ]]
  [[ "$output" == *"Deleted artifact 2301 of 2000-01-01, report-2301 (1.0 MB, run 1301)"* ]]
  grep -qx 'artifacts-deleted=4' "$GITHUB_OUTPUT"
  grep -qx "artifacts-bytes-freed=$((4 * 1048576))" "$GITHUB_OUTPUT"
  grep -qx 'deleted=0' "$GITHUB_OUTPUT"
  grep -qxF "Artifacts created before $(days_ago 3) (3 days) of any completed run: **4 deleted, 4.0 MB freed**." \
    "$GITHUB_STEP_SUMMARY"
}

@test "an expired artifact is skipped, and with no old one left no run state is asked" {
  artifact 2401 1401 2000-01-01T00:00:00Z 1048576 true
  artifact 2402 1402 2000-01-02T00:00:00Z
  ARTIFACTS_OLDER_THAN_DAYS=3 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(artifact_deletions)" = "2402" ]
  grep -qx 'artifacts-deleted=1' <<< "$output"

  : > "$STUB_DIR/curl.log"
  rm "$STUB_DIR/artifacts.jsonl"
  artifact 2403 1403 2000-01-01T00:00:00Z 1048576 true
  artifact 2404 1404 "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ARTIFACTS_OLDER_THAN_DAYS=3 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(artifact_deletions)" = "" ]
  refute grep -q 'status=queued' "$STUB_DIR/curl.log"
}

@test "the old artifacts of a run not completed stay: a later job may still download them" {
  artifact 2801 1801 2000-01-01T00:00:00Z
  artifact 2802 1802 2000-01-01T00:00:00Z
  artifact 2803 1803 2000-01-01T00:00:00Z
  runs_in_state waiting 1801
  runs_in_state in_progress 1802
  ARTIFACTS_OLDER_THAN_DAYS=3 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(artifact_deletions)" = "2803" ]
  for state in queued in_progress waiting requested pending; do
    grep -qx "GET /actions/runs?status=${state}&per_page=100&page=1" "$STUB_DIR/curl.log"
  done
}

@test "a dry run deletes no artifact, prints what would go and what it would free" {
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md" GITHUB_OUTPUT="$BATS_TEST_TMPDIR/output"
  artifact 2501 1501 2000-01-01T00:00:00Z 1572864 false sitespeed-result-mobile
  artifact 2502 1502 2000-01-02T00:00:00Z 524288 false '::error::x`y'
  DRY_RUN=true ARTIFACTS_OLDER_THAN_DAYS=3 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  refute grep -q '^DELETE' "$STUB_DIR/curl.log"
  [[ "$output" == *"Would delete artifact 2501 of 2000-01-01, sitespeed-result-mobile (1.5 MB, run 1501)"* ]]
  # A name is printed with unusual characters replaced.
  [[ "$output" == *"Would delete artifact 2502 of 2000-01-02, __error__x_y (0.5 MB, run 1502)"* ]]
  refute grep -q '::error::x' <<< "$output"
  grep -qx 'artifacts-deleted=2' "$GITHUB_OUTPUT"
  grep -qx 'artifacts-bytes-freed=2097152' "$GITHUB_OUTPUT"
  grep -qF '**2 would be deleted, 2.0 MB would be freed**' "$GITHUB_STEP_SUMMARY"
}

@test "artifacts and runs share MAX_DELETIONS, artifacts first, DELETE_INTERVAL between any two deletions" {
  stub_sleep
  old_run 1601 1 2000-01-01T00:00:00Z
  old_run 1602 1 2000-01-02T00:00:00Z
  artifact 2602 1700 2000-01-04T00:00:00Z
  artifact 2601 1700 2000-01-03T00:00:00Z
  KEEP_RUNS=0 MAX_DELETIONS=3 ARTIFACTS_OLDER_THAN_DAYS=3 DELETE_INTERVAL=2 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(sed -n 's|^DELETE /actions/||p' "$STUB_DIR/curl.log" | paste -sd' ' -)" = "artifacts/2601 artifacts/2602 runs/1601" ]
  [ "$(paste -sd' ' - < "$STUB_DIR/sleep.log")" = "2 2" ]
  [[ "$output" == *"At most 3 deletions in this run, the artifacts first."* ]]
  grep -qx 'artifacts-deleted=2' <<< "$output"
  grep -qx 'deleted=1' <<< "$output"
  grep -qx 'remaining=1' <<< "$output"
}

@test "artifacts beyond MAX_DELETIONS are left for the next run, the runs waiting behind them" {
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md"
  old_run 1651 1 2000-01-01T00:00:00Z
  artifact 2651 1700 2000-01-02T00:00:00Z
  artifact 2652 1700 2000-01-03T00:00:00Z
  KEEP_RUNS=0 MAX_DELETIONS=1 ARTIFACTS_OLDER_THAN_DAYS=3 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(artifact_deletions)" = "2651" ]
  [ "$(deletions)" = "" ]
  grep -qx 'remaining=1' <<< "$output"
  # One line for the artifacts, one for the runs.
  [ "$(grep -cxF '1 more left for the next run (max-deletions: 1).' "$GITHUB_STEP_SUMMARY")" -eq 2 ]
}

@test "the artifacts are read page after page, and one listed twice counts once" {
  jq -n --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{artifacts: [range(100) | {id: (3000 + .), name: "young",
    size_in_bytes: 1, created_at: $now, expired: false, workflow_run: {id: 1}}]}' > "$STUB_DIR/artifacts-1.json"
  # 2701 is on both pages: a new upload pushed it from one page to the next.
  jq -n '{artifacts: [{id: 2701, created_at: "2000-01-01T00:00:00Z"}, {id: 2701, created_at: "2000-01-01T00:00:00Z"},
    {id: 2702, created_at: "2000-01-02T00:00:00Z"}] | map(. + {name: "old", size_in_bytes: 1, expired: false,
    workflow_run: {id: 2}})}' > "$STUB_DIR/artifacts-2.json"
  ARTIFACTS_OLDER_THAN_DAYS=3 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^GET /actions/artifacts?' "$STUB_DIR/curl.log")" -eq 2 ]
  grep -qx 'GET /actions/artifacts?per_page=100&page=2' "$STUB_DIR/curl.log"
  [ "$(artifact_deletions)" = "2701 2702" ]
}

@test "the artifact listing stops after a hundred pages and the summary says so" {
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md"
  jq -n '{artifacts: [range(100) | {id: (5000 + .), name: "gone", size_in_bytes: 1,
    created_at: "2000-01-01T00:00:00Z", expired: true, workflow_run: {id: 1}}]}' > "$STUB_DIR/page.json"
  for page in $(seq 1 101); do
    cp "$STUB_DIR/page.json" "$STUB_DIR/artifacts-$page.json"
  done
  ARTIFACTS_OLDER_THAN_DAYS=3 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^GET /actions/artifacts?' "$STUB_DIR/curl.log")" -eq 100 ]
  grep -qF 'GitHub lists at least 10000 artifacts, the newest first: older ones were not looked at.' \
    "$GITHUB_STEP_SUMMARY"
}

@test "an artifact already gone is not counted; any other refusal stops the run with GitHub's answer" {
  artifact 2901 1901 2000-01-01T00:00:00Z
  artifact 2902 1901 2000-01-02T00:00:00Z 2097152
  echo 404 > "$STUB_DIR/delete-artifact-2901.status"
  ARTIFACTS_OLDER_THAN_DAYS=3 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already gone: artifact 2901"* ]]
  grep -qx 'artifacts-deleted=1' <<< "$output"
  grep -qx 'artifacts-bytes-freed=2097152' <<< "$output"

  : > "$STUB_DIR/curl.log"
  echo 403 > "$STUB_DIR/delete-artifact-2902.status"
  old_run 1902 1 2000-01-01T00:00:00Z
  KEEP_RUNS=0 ARTIFACTS_OLDER_THAN_DAYS=3 run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GitHub answered 403 deleting artifact 2902"*"Resource not accessible by integration"* ]]
  [ "$(deletions)" = "" ]
}

@test "ARTIFACTS_OLDER_THAN_DAYS is a whole number from 0 to 36500, stored without leading zeros" {
  for value in -1 36501 x 1.5 ' 3' 3d; do
    run env "ARTIFACTS_OLDER_THAN_DAYS=$value" bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ARTIFACTS_OLDER_THAN_DAYS must be a whole number from 0 to 36500, not '$value'"* ]]
  done
  [ ! -f "$STUB_DIR/curl.log" ]
  ARTIFACTS_OLDER_THAN_DAYS=007 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Artifacts created before $(days_ago 7) (7 days) of any completed run: 0 to delete."* ]]
}
