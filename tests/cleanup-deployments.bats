#!/usr/bin/env bats
# Tests for .github/actions/cleanup-deployments/cleanup-deployments.sh

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/cleanup-deployments/cleanup-deployments.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p bin tmp stub
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  export RUNNER_TEMP="$TMPDIR"
  export STUB_DIR="$BATS_TEST_TMPDIR/stub"
  export GITHUB_TOKEN=secret-token GITHUB_REPOSITORY=o/r GITHUB_API_URL=https://api.github.test
  export DELETE_INTERVAL=0
  unset GITHUB_OUTPUT GITHUB_STEP_SUMMARY KEEP OLDER_THAN_DAYS MAX_DELETIONS DRY_RUN
  : > "$STUB_DIR/deployments.jsonl"
  stub_curl
}

# A curl that answers from STUB_DIR and logs "METHOD PATH" in curl.log.
# deployments-N.json is page N of the list; status-ID and delete-ID hold the
# HTTP status of the two calls for a deployment (201 and 204 by default).
stub_curl() {
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
out=/dev/stdout method=GET url="" data=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -X) method="$2"; shift 2 ;;
    -d) data="$2"; shift 2 ;;
    -H) case "$2" in @*) cat "${2#@}" >> "$STUB_DIR/curl-headers.log" ;; esac; shift 2 ;;
    -w | --retry | --retry-delay | --max-time) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
path="${url#https://api.github.test/repos/o/r}"
printf '%s %s %s\n' "$method" "$path" "$data" | sed 's/ $//' >> "$STUB_DIR/curl.log"
reply() { printf '%s' "$2" > "$out"; printf '%s' "$1"; }
page="$(printf '%s' "$path" | sed -n 's/.*[?&]page=\([0-9]*\).*/\1/p')"
case "$method $path" in
  "GET /deployments?"*)
    if [ -f "$STUB_DIR/list-status" ]; then
      reply "$(cat "$STUB_DIR/list-status")" '{"message":"Resource not accessible by integration"}'
    else
      reply 200 "$(cat "$STUB_DIR/deployments-$page.json" 2> /dev/null || echo '[]')"
    fi
    ;;
  "POST /deployments/"*"/statuses")
    id="${path#/deployments/}"; id="${id%%/*}"
    reply "$(cat "$STUB_DIR/status-$id" 2> /dev/null || echo 201)" '{"message":"nope"}'
    ;;
  "DELETE /deployments/"*)
    reply "$(cat "$STUB_DIR/delete-${path#/deployments/}" 2> /dev/null || echo 204)" '{"message":"nope"}'
    ;;
  *) reply 500 '{"message":"unexpected request"}' ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
}

# days_ago N: an ISO timestamp N days ago.
days_ago() {
  jq -rn --argjson d "$1" '(now | floor) - $d * 86400 | strftime("%Y-%m-%dT%H:%M:%SZ")'
}

# deployment ID ENVIRONMENT DAYS: a deployment GitHub lists, DAYS days old.
deployment() {
  jq -cn --argjson id "$1" --arg env "$2" --arg created "$(days_ago "$3")" \
    '{id: $id, environment: $env, created_at: $created, sha: ("a" * 40), extra: "ignored"}' \
    >> "$STUB_DIR/deployments.jsonl"
  jq -s 'sort_by(.created_at) | reverse' "$STUB_DIR/deployments.jsonl" > "$STUB_DIR/deployments-1.json"
}

# deletions: the deployments the script asked GitHub to delete, in order.
deletions() {
  sed -n 's|^DELETE /deployments/||p' "$STUB_DIR/curl.log" | paste -sd' ' -
}

@test "keeps the 5 most recent of each environment and anything younger than 30 days" {
  for i in 1 2 3 4 5 6 7 8; do deployment "$i" prod "$((100 - i))"; done   # 8 old prod: 1 is the oldest
  deployment 20 dev 90
  deployment 21 dev 80
  deployment 30 preview 10   # young
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(deletions)" = "1 2 3" ]
  [[ "$output" == *"Deleted 3 of 11 deployment(s); 0 failed, 0 left for a later run."* ]]
}

@test "a young deployment stays even beyond the keep count" {
  for i in 1 2 3 4 5 6 7; do deployment "$i" prod "$i"; done
  KEEP=2 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(deletions)" = "" ]
  [[ "$output" == *"Deleted 0 of 7 deployment(s)"* ]]
}

@test "each deployment is set inactive, then deleted, oldest first" {
  deployment 1 prod 60
  deployment 2 prod 50
  deployment 3 prod 40
  KEEP=1 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(grep -v '^GET' "$STUB_DIR/curl.log" | paste -sd'|' -)" = \
    'POST /deployments/1/statuses {"state":"inactive"}|DELETE /deployments/1|POST /deployments/2/statuses {"state":"inactive"}|DELETE /deployments/2' ]
  grep -qx 'Authorization: Bearer secret-token' "$STUB_DIR/curl-headers.log"
  [[ "$output" != *secret-token* ]]
}

@test "a dry run deletes nothing and says what it would delete" {
  deployment 1 prod 60
  deployment 2 prod 50
  KEEP=1 DRY_RUN=true GITHUB_OUTPUT="$BATS_TEST_TMPDIR/out" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(deletions)" = "" ]
  [ "$(grep -c -v '^GET' "$STUB_DIR/curl.log")" -eq 0 ]
  [[ "$output" == *"Would delete deployment 1 of "*" to prod (aaaaaaa)"* ]]
  [[ "$output" == *"Would delete 1 of 2 deployment(s)"* ]]
  grep -qx 'deleted=1' "$BATS_TEST_TMPDIR/out"
}

@test "max-deletions bounds a run and reports what is left" {
  for i in 1 2 3 4 5 6; do deployment "$i" prod "$((100 - i))"; done
  KEEP=1 MAX_DELETIONS=2 GITHUB_OUTPUT="$BATS_TEST_TMPDIR/out" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(deletions)" = "1 2" ]
  [[ "$output" == *"Deleted 2 of 6 deployment(s); 0 failed, 3 left for a later run."* ]]
  grep -qx 'remaining=3' "$BATS_TEST_TMPDIR/out"
}

@test "a deployment that cannot be retired is skipped with a warning, not deleted" {
  deployment 1 prod 60
  deployment 2 prod 50
  deployment 3 prod 40
  echo 422 > "$STUB_DIR/status-1"
  KEEP=1 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(deletions)" = "2" ]
  [[ "$output" == *"::warning::Could not retire deployment 1 "*"GitHub answered 422 nope"* ]]
  [[ "$output" == *"Deleted 1 of 3 deployment(s); 1 failed, 0 left"* ]]
}

@test "fails when no deletion works, or when the list is refused" {
  deployment 1 prod 60
  deployment 2 prod 50
  echo 403 > "$STUB_DIR/delete-1"
  KEEP=1 run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::no deployment could be deleted (1 failed): does the job grant deployments: write?"* ]]

  echo 403 > "$STUB_DIR/list-status"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::GitHub answered 403 listing the deployments: Resource not accessible by integration"* ]]
}

@test "reads every page of the list" {
  jq -n --arg old "$(days_ago 90)" '[range(0; 100) | {id: (1000 + .), environment: "prod", created_at: $old, sha: ("b" * 40)}]' \
    > "$STUB_DIR/deployments-1.json"
  jq -n --arg older "$(days_ago 200)" '[{id: 1, environment: "prod", created_at: $older, sha: ("c" * 40)}]' \
    > "$STUB_DIR/deployments-2.json"
  DRY_RUN=true MAX_DELETIONS=1 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Would delete deployment 1 of "* ]]
  [[ "$output" == *"of 101 deployment(s); 0 failed, 95 left"* ]]
}

@test "rejects bad settings before any request" {
  for setting in KEEP=0 KEEP=101 OLDER_THAN_DAYS=-1 MAX_DELETIONS=401 MAX_DELETIONS=abc DRY_RUN=yes \
    GITHUB_REPOSITORY=nope GITHUB_API_URL=http://api.github.test; do
    run env "$setting" bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == "::error::"* ]]
  done
  [ ! -e "$STUB_DIR/curl.log" ]
}
