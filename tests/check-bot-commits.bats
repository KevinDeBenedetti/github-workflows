#!/usr/bin/env bats
# Tests for .github/actions/check-bot-commits/check-bot-commits.sh

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/check-bot-commits/check-bot-commits.sh"

load helpers/fake-github

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p bin tmp stub
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  export RUNNER_TEMP="$TMPDIR"
  export STUB_DIR="$BATS_TEST_TMPDIR/stub"
  export GITHUB_TOKEN=secret-token GITHUB_REPOSITORY=o/r GITHUB_API_URL=https://api.github.test
  export PR_NUMBER=7 GITHUB_OUTPUT="$BATS_TEST_TMPDIR/output" GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary"
  unset ALLOWED_BOTS FAIL_ON_BOT_COMMITS PR_COMMITS
  : > "$GITHUB_OUTPUT"
  : > "$GITHUB_STEP_SUMMARY"
  fake_github https://api.github.test/repos/o/r "$(cat << 'EOF'
case "$method $path" in
  "GET /pulls/7/commits?per_page=100&page="*)
    if [ -f "$STUB_DIR/status" ]; then
      reply "$(cat "$STUB_DIR/status")" '{"message":"Resource not accessible by integration"}'
    fi
    reply 200 "$(cat "$STUB_DIR/commits-$page.json" 2> /dev/null || echo '[]')"
    ;;
esac
EOF
  )"
}

# commit LOGIN TYPE NAME EMAIL [PAGE]: a commit of the pull request, on page
# PAGE (1 by default). An empty LOGIN is a commit linked to no account.
commit() {
  local file="$STUB_DIR/commits-${5:-1}.json" n
  [ -f "$file" ] || echo '[]' > "$file"
  n="$(jq length "$file")"
  jq --arg login "$1" --arg type "$2" --arg name "$3" --arg email "$4" --arg sha "$(printf '%040d' "$((n + 1))")" \
    '. + [{sha: $sha, author: (if $login == "" then null else {login: $login, type: $type} end),
           commit: {author: {name: $name, email: $email}}}]' "$file" > "$file.new"
  mv "$file.new" "$file"
}

human() { commit alice User Alice alice@example.test "${1:-1}"; }

@test "human commits pass, with a summary row each" {
  human
  commit bob User Bob bob@example.test
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅ 2 commit(s) checked: no bot commit outside allowed-bots."* ]]
  [ "$(cat "$GITHUB_OUTPUT")" = $'checked=2\nblocked=0' ]
  grep -qx '| 0000000 | alice | Human |' "$GITHUB_STEP_SUMMARY"
  grep -qx '| 0000000 | bob | Human |' "$GITHUB_STEP_SUMMARY"
  # The token stays in a header file, never on a command line.
  run grep -c secret-token "$STUB_DIR/curl-args.log"
  [ "$output" = 0 ]
  grep -qx 'Authorization: Bearer secret-token' "$STUB_DIR/curl-headers.log"
}

@test "a bot is recognised by its account type, its login or its no-reply e-mail" {
  commit some-app Bot "Some App" app@example.test
  commit helper[bot] User Helper helper@example.test
  commit carol User Carol '12345+tool[bot]@users.noreply.github.com'
  human
  FAIL_ON_BOT_COMMITS=false run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_OUTPUT")" = $'checked=4\nblocked=3' ]
  [[ "$output" == *"❌ 0000000 bot commit: some-app <app@example.test>"* ]]
  [[ "$output" == *"❌ 0000000 bot commit: helper[bot]"* ]]
  [[ "$output" == *"❌ 0000000 bot commit: carol"* ]]
  [[ "$output" == *"::warning::3 bot commit(s) in pull request #7, allowed because fail-on-bot-commits is false"* ]]
}

@test "a bot commit fails the check unless its account is allowed" {
  commit 'dependabot[bot]' Bot dependabot '49699333+dependabot[bot]@users.noreply.github.com'
  human
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::1 bot commit(s) in pull request #7"* ]]
  grep -qF '> ❌ **1 bot commit(s).**' "$GITHUB_STEP_SUMMARY"
  : > "$GITHUB_STEP_SUMMARY"
  : > "$GITHUB_OUTPUT"
  ALLOWED_BOTS='["renovate[bot]","dependabot[bot]"]' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅ 0000000 allowed bot: dependabot[bot]"* ]]
  [ "$(cat "$GITHUB_OUTPUT")" = $'checked=2\nblocked=0' ]
  grep -qF 'Bot (allowed)' "$GITHUB_STEP_SUMMARY"
}

@test "a commit linked to no account is a bot's by its name, and never allowed by it" {
  # Anyone can write renovate[bot] as their author name.
  commit '' '' 'renovate[bot]' mallory@example.test
  ALLOWED_BOTS='["renovate[bot]"]' run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"❌ 0000000 bot commit: renovate[bot] <mallory@example.test> (no GitHub account)"* ]]
  [ "$(cat "$GITHUB_OUTPUT")" = $'checked=1\nblocked=1' ]
  # A plain name with no account is a human.
  rm "$STUB_DIR/commits-1.json"
  commit '' '' 'Dave' dave@example.test
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"👤 0000000 Dave <dave@example.test> (no GitHub account)"* ]]
}

@test "an author name cannot write links, HTML or escapes into the summary" {
  commit '' '' 'x](https://evil.test) <img src=y> `a|b` *c* \n' x@example.test
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qxF '| 0000000 | x\](https://evil.test) &lt;img src=y&gt; \`a\|b\` \*c\* \\n &lt;x@example.test&gt; (no GitHub account) | Human |' \
    "$GITHUB_STEP_SUMMARY"
  # Title, table head and rule, one row, verdict: no line was added.
  [ "$(grep -c . "$GITHUB_STEP_SUMMARY")" -eq 5 ]
}

@test "control characters in an author field cannot break a line" {
  commit '' '' $'Eve\t\x01name' $'e@x.test\r'
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"👤 0000000 Eve  name <e@x.test > (no GitHub account)"* ]]
}

@test "every page is read, up to the 250 commits GitHub lists" {
  local i
  for i in $(seq 100); do human 1; done
  for i in $(seq 100); do human 2; done
  for i in $(seq 49); do human 3; done
  commit 'renovate[bot]' Bot renovate r@example.test 3
  PR_COMMITS=250 run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [ "$(cat "$GITHUB_OUTPUT")" = $'checked=250\nblocked=1' ]
  [ "$(grep -c 'GET /pulls/7/commits' "$STUB_DIR/curl.log")" -eq 3 ]
  grep -qx 'GET /pulls/7/commits?per_page=100&page=3' "$STUB_DIR/curl.log"
}

@test "a pull request with more commits than GitHub lists fails, even in warn-only mode" {
  human
  PR_COMMITS=300 FAIL_ON_BOT_COMMITS=false run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::pull request #7 has 300 commits and GitHub lists 1 of them (250 at most): refusing to pass unchecked"* ]]
  PR_COMMITS=1 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "an API error fails the check instead of passing unchecked" {
  echo 403 > "$STUB_DIR/status"
  FAIL_ON_BOT_COMMITS=false run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::GitHub answered 403 listing the commits of pull request #7: Resource not accessible by integration — refusing to pass unchecked"* ]]
  [ ! -s "$GITHUB_OUTPUT" ]
}

@test "an empty pull request passes; outside a pull request nothing is checked" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qx 'No commit in this pull request.' "$GITHUB_STEP_SUMMARY"
  PR_NUMBER='' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::notice::Not a pull request: no commit to check."* ]]
  [ "$(grep -c . "$STUB_DIR/curl.log")" -eq 1 ]
}

@test "rejects unusable settings" {
  ALLOWED_BOTS='dependabot[bot]' run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::ALLOWED_BOTS must be a JSON array of logins"* ]]
  ALLOWED_BOTS='[1]' run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  FAIL_ON_BOT_COMMITS=yes run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL_ON_BOT_COMMITS must be true or false, not 'yes'"* ]]
  PR_NUMBER='7;x' run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  PR_COMMITS=x run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  GITHUB_API_URL=http://api.github.test run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GITHUB_API_URL must be an https:// URL"* ]]
  [ ! -s "$STUB_DIR/curl.log" ]
}
