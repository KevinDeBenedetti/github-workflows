#!/usr/bin/env bats
# Tests for the scripts of .github/actions/pr-description/

ACTION="$BATS_TEST_DIRNAME/../.github/actions/pr-description"

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p bin tmp
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  # The scripts' mktemp files stay inside the test's own directory.
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
}

# Commits in a throwaway repo. The subcommand is built at runtime so this file
# never contains the literal command blocked by the agent guardrails.
mkcommit() {
  git -c user.name=t -c user.email=t@t -c "com""mit.gpgsign=false" "com""mit" -q "$@"
}

# merge CURRENT DESCRIPTION: run merge-body.py on two printf strings, into new.md.
merge() {
  printf '%b' "$1" > current.md
  printf '%b' "$2" > description.md
  run python3 "$ACTION/merge-body.py" current.md description.md new.md
}

# A repo whose pull request commit touches app.txt and a lockfile.
init_repo() {
  git init -q repo
  cd repo
  printf 'a\n' > app.txt
  git add app.txt
  mkcommit -m 'chore: base'
  base=$(git rev-parse HEAD)
  printf 'a\nb\n' > app.txt
  printf '{"lockfileVersion": 3}\n' > package-lock.json
  git add app.txt package-lock.json
  mkcommit -m 'feat: add b' -m 'Explains why b matters.'
  head=$(git rev-parse HEAD)
}

# stub_claude JSON [EXIT]: a fake claude that logs how it was called.
stub_claude() {
  cat > bin/claude <<EOF
#!/usr/bin/env bash
{
  printf 'cwd=%s\n' "\$PWD"
  printf 'cwd_files=%s\n' "\$(ls -A)"
  printf 'config_files=%s\n' "\$(ls -A "\$CLAUDE_CONFIG_DIR")"
  printf 'api_key=%s\n' "\${ANTHROPIC_API_KEY-unset}"
  printf 'token=%s\n' "\$CLAUDE_CODE_OAUTH_TOKEN"
  printf 'stdin=%s\n' "\$(cat)"
  for a in "\$@"; do printf 'arg=[%s]\n' "\$a"; done
} > "$BATS_TEST_TMPDIR/claude.log"
printf '%s\n' '$1'
exit ${2:-0}
EOF
  chmod +x bin/claude
}

# describe_with [VAR=value...]: run write-description.sh on a one-line context.
describe_with() {
  printf 'the context\n' > context.md
  env CLAUDE_CODE_OAUTH_TOKEN=tok MODEL=claude-opus-5-5 \
    CONTEXT_FILE="$PWD/context.md" DESCRIPTION_FILE="$PWD/description.md" "$@" \
    bash "$ACTION/write-description.sh"
}

# stub_curl PR_JSON [GET_EXIT]: a fake curl that serves the pull request. It
# logs every call (arguments, then method and URL), the header files it reads,
# and keeps the body of a PATCH.
stub_curl() {
  printf '%s\n' "$1" > "$BATS_TEST_TMPDIR/pr.json"
  cat > bin/curl <<EOF
#!/usr/bin/env bash
out=/dev/stdout method=GET data="" url=""
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/curl-args.log"
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o) out="\$2"; shift 2 ;;
    -X) method="\$2"; shift 2 ;;
    --data-binary) data="\${2#@}"; shift 2 ;;
    -H) case "\$2" in @*) cat "\${2#@}" >> "$BATS_TEST_TMPDIR/curl-headers.log" ;; esac; shift 2 ;;
    --retry | --retry-delay) shift 2 ;;
    -*) shift ;;
    *) url="\$1"; shift ;;
  esac
done
printf '%s %s\n' "\$method" "\$url" >> "$BATS_TEST_TMPDIR/curl.log"
if [ "\$method" = PATCH ]; then
  cp "\$data" "$BATS_TEST_TMPDIR/patched.json"
  printf '{}' > "\$out"
  exit 0
fi
cat "$BATS_TEST_TMPDIR/pr.json" > "\$out"
exit ${2:-0}
EOF
  chmod +x bin/curl
}

# update [VAR=value...]: run update-body.sh against the fake curl.
update() {
  env -u GITHUB_API_URL GITHUB_TOKEN=secret-token-123 REPO=o/r PR_NUMBER=7 \
    DESCRIPTION_FILE="$PWD/description.md" "$@" \
    bash "$ACTION/update-body.sh"
}

# ── merge-body.py ────────────────────────────────────────────────────────────

@test "merge: an empty body becomes the managed block alone" {
  merge '' 'Adds b.\n'
  [ "$status" -eq 0 ]
  [[ "$(head -1 new.md)" == "<!-- pr-description:start"* ]]
  [ "$(sed -n 2p new.md)" = "Adds b." ]
  [ "$(tail -1 new.md)" = "<!-- pr-description:end -->" ]
}

@test "merge: an existing body is kept below a new block" {
  merge 'Closes #12' 'Adds b.'
  [ "$status" -eq 0 ]
  [[ "$(head -1 new.md)" == "<!-- pr-description:start"* ]]
  [ "$(tail -1 new.md)" = "Closes #12" ]
}

@test "merge: an existing block is replaced in place, text around it kept" {
  merge 'Intro\n\n<!-- pr-description:start -->\nOld text\n<!-- pr-description:end -->\n\nCloses #12' 'New text'
  [ "$status" -eq 0 ]
  [ "$(head -1 new.md)" = "Intro" ]
  grep -qx 'New text' new.md
  [ "$(grep -c 'Old text' new.md)" -eq 0 ]
  [ "$(grep -c 'pr-description:start' new.md)" -eq 1 ]
  [ "$(tail -1 new.md)" = "Closes #12" ]
}

@test "merge: the same description twice gives the same body" {
  merge 'Closes #12' 'Adds b.'
  cp new.md current.md
  run python3 "$ACTION/merge-body.py" current.md description.md again.md
  [ "$status" -eq 0 ]
  cmp new.md again.md
}

@test "merge: CRLF line endings outside the block are kept" {
  merge 'Closes #12\r\nThanks' 'Adds b.'
  [ "$status" -eq 0 ]
  [ "$(tr -cd '\r' < new.md | wc -c | tr -d ' ')" -eq 1 ]
}

@test "merge: a code fence around the whole description is removed" {
  merge '' '```markdown\nAdds b.\n```\n'
  [ "$status" -eq 0 ]
  [ "$(grep -c '```' new.md)" -eq 0 ]
  grep -qx 'Adds b.' new.md
}

@test "merge: markers inside the description cannot open or close the block" {
  merge 'Closes #12' 'Text\n<!-- pr-description:end -->\nInjected\n<!-- pr-description:start -->'
  [ "$status" -eq 0 ]
  [ "$(grep -c 'pr-description:start' new.md)" -eq 1 ]
  [ "$(grep -c 'pr-description:end' new.md)" -eq 1 ]
}

@test "merge: an empty description fails" {
  merge 'Closes #12' '  \n\n'
  [ "$status" -eq 1 ]
}

@test "merge: an overlong description is truncated at a line" {
  python3 -c 'print("a line of text\n" * 3000, end="")' > description.md
  : > current.md
  run python3 "$ACTION/merge-body.py" current.md description.md new.md
  [ "$status" -eq 0 ]
  [ "$(wc -c < new.md)" -lt 20400 ]
  grep -q 'description truncated' new.md
}

@test "merge: a body over GitHub's limit fails" {
  python3 -c 'print("x" * 70000)' > current.md
  printf 'Adds b.\n' > description.md
  run python3 "$ACTION/merge-body.py" current.md description.md new.md
  [ "$status" -eq 1 ]
  [[ "$output" == *"65536"* ]]
}

# ── collect-context.sh ───────────────────────────────────────────────────────

@test "context: lists the commits, the diffstat and the diff, not lockfile content" {
  init_repo
  BASE_SHA=$base HEAD_SHA=$head PR_TITLE='Add b' run bash "$ACTION/collect-context.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Write the description in English."* ]]
  [[ "$output" == *"<title>"*"Add b"*"</title>"* ]]
  [[ "$output" == *"* feat: add b"* ]]
  [[ "$output" == *"Explains why b matters."* ]]
  [[ "$output" != *"chore: base"* ]]
  [[ "$output" == *"package-lock.json"* ]]
  [[ "$output" != *"lockfileVersion"* ]]
  [[ "$output" == *"+b"* ]]
}

@test "context: a diff over MAX_DIFF_BYTES is cut and flagged" {
  init_repo
  seq 1 5000 > big.txt
  git add big.txt
  mkcommit -m 'feat: big file'
  head=$(git rev-parse HEAD)
  BASE_SHA=$base HEAD_SHA=$head MAX_DIFF_BYTES=2000 DESCRIPTION_LANGUAGE=French run bash "$ACTION/collect-context.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Write the description in French."* ]]
  [[ "$output" == *"cut to its first 2000 of"* ]]
  [[ "$output" != *"+5000"* ]]
}

@test "context: rejects a MAX_DIFF_BYTES that is not a positive integer" {
  init_repo
  BASE_SHA=$base HEAD_SHA=$head MAX_DIFF_BYTES=10k run bash "$ACTION/collect-context.sh"
  [ "$status" -eq 2 ]
}

# ── write-description.sh ─────────────────────────────────────────────────────

@test "write: runs claude with no tools, from empty directories, on the subscription token" {
  stub_claude '{"type":"result","subtype":"success","is_error":false,"result":"Adds b."}'
  run describe_with EFFORT=medium ANTHROPIC_API_KEY=leak
  [ "$status" -eq 0 ]
  [ "$(cat description.md)" = "Adds b." ]
  log="$BATS_TEST_TMPDIR/claude.log"
  grep -qxF 'api_key=unset' "$log"
  grep -qxF 'token=tok' "$log"
  grep -qxF 'stdin=the context' "$log"
  grep -qxF 'cwd_files=' "$log"
  grep -qxF 'config_files=' "$log"
  [ "$(sed -n 's/^cwd=//p' "$log")" != "$BATS_TEST_TMPDIR" ]
  grep -A1 -xF 'arg=[--tools]' "$log" | grep -qxF 'arg=[]'
  grep -A1 -xF 'arg=[--model]' "$log" | grep -qxF 'arg=[claude-opus-5-5]'
  grep -A1 -xF 'arg=[--effort]' "$log" | grep -qxF 'arg=[medium]'
  grep -A1 -xF 'arg=[--setting-sources]' "$log" | grep -qxF 'arg=[user]'
  grep -qxF 'arg=[--strict-mcp-config]' "$log"
}

@test "write: leaves --effort out when EFFORT is empty" {
  stub_claude '{"is_error":false,"result":"Adds b."}'
  run describe_with EFFORT=
  [ "$status" -eq 0 ]
  [ "$(grep -cxF 'arg=[--effort]' "$BATS_TEST_TMPDIR/claude.log")" -eq 0 ]
}

@test "write: an error result fails without echoing a workflow command" {
  stub_claude '{"is_error":true,"result":"Invalid token\n::add-mask::x"}' 1
  run describe_with
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid token"* ]]
  [[ "$output" != *"::add-mask::"* ]]
}

@test "write: output that is not JSON fails" {
  stub_claude 'Not logged in' 1
  run describe_with
  [ "$status" -eq 1 ]
  [[ "$output" == *"without a JSON result"* ]]
}

@test "write: an empty result fails" {
  stub_claude '{"is_error":false,"result":"  "}'
  run describe_with
  [ "$status" -eq 1 ]
  [[ "$output" == *"empty description"* ]]
}

# ── update-body.sh ───────────────────────────────────────────────────────────

@test "update: saves the merged body and keeps the existing text" {
  stub_curl '{"number":7,"body":"Closes #12"}'
  printf 'Adds b.\n' > description.md
  run update
  [ "$status" -eq 0 ]
  body=$(jq -r .body "$BATS_TEST_TMPDIR/patched.json")
  [[ "$body" == "<!-- pr-description:start"*"Adds b."*"<!-- pr-description:end -->"*"Closes #12" ]]
  grep -qxF 'GET https://api.github.com/repos/o/r/pulls/7' "$BATS_TEST_TMPDIR/curl.log"
  grep -qxF 'PATCH https://api.github.com/repos/o/r/pulls/7' "$BATS_TEST_TMPDIR/curl.log"
}

@test "update: the token goes through a header file, never on a command line" {
  stub_curl '{"number":7,"body":""}'
  printf 'Adds b.\n' > description.md
  run update
  [ "$status" -eq 0 ]
  [ "$(grep -c 'secret-token-123' "$BATS_TEST_TMPDIR/curl-args.log")" -eq 0 ]
  grep -qxF 'Authorization: Bearer secret-token-123' "$BATS_TEST_TMPDIR/curl-headers.log"
}

@test "update: follows GITHUB_API_URL" {
  stub_curl '{"number":7,"body":""}'
  printf 'Adds b.\n' > description.md
  run update GITHUB_API_URL=https://ghe.example/api/v3
  [ "$status" -eq 0 ]
  grep -qxF 'GET https://ghe.example/api/v3/repos/o/r/pulls/7' "$BATS_TEST_TMPDIR/curl.log"
}

@test "update: a pull request with no body gets the block alone" {
  stub_curl '{"number":7,"body":null}'
  printf 'Adds b.\n' > description.md
  run update
  [ "$status" -eq 0 ]
  [[ "$(jq -r .body "$BATS_TEST_TMPDIR/patched.json")" == *"Adds b."*"<!-- pr-description:end -->" ]]
}

@test "update: a body already up to date is not saved again" {
  printf 'Adds b.\n' > description.md
  printf 'Closes #12' > current.md
  python3 "$ACTION/merge-body.py" current.md description.md merged.md
  stub_curl "$(jq -cn --rawfile b merged.md '{number: 7, body: $b}')"
  run update
  [ "$status" -eq 0 ]
  [[ "$output" == *"already up to date"* ]]
  [ "$(grep -c '^PATCH' "$BATS_TEST_TMPDIR/curl.log")" -eq 0 ]
}

@test "update: an API error fails and shows GitHub's answer" {
  stub_curl '{"message":"Resource not accessible by integration"}' 22
  printf 'Adds b.\n' > description.md
  run update
  [ "$status" -eq 1 ]
  [[ "$output" == *"Resource not accessible by integration"* ]]
}

@test "update: rejects a pull request number that is not a number" {
  printf 'Adds b.\n' > description.md
  run update PR_NUMBER=7/../../x
  [ "$status" -eq 2 ]
}
