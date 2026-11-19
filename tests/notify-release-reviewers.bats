#!/usr/bin/env bats
# Tests for .github/actions/notify-release-reviewers/notify-release-reviewers.sh,
# with a fake gh on PATH.

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/notify-release-reviewers/notify-release-reviewers.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p bin stub
  export STUB="$BATS_TEST_TMPDIR/stub"
  # The fake logs each call on one line of gh.log. `pr list` prints
  # stub/list, `api …/issues/N/timeline` applies its --jq filter to
  # stub/timeline-N.json; a stub/fail-<list|timeline-N|edit-N> file fails that call.
  cat > bin/gh << 'SH'
#!/usr/bin/env bash
echo "$*" >> "$STUB/gh.log"
case "$1 $2" in
  "pr list")
    [ ! -f "$STUB/fail-list" ] || { echo 'HTTP 502' >&2; exit 1; }
    cat "$STUB/list" 2> /dev/null ;;
  "api --paginate")
    n="${3#repos/o/r/issues/}"; n="${n%/timeline}"
    [ ! -f "$STUB/fail-timeline-$n" ] || { echo 'HTTP 404' >&2; exit 1; }
    jq -r "$5" "$STUB/timeline-$n.json" 2> /dev/null || jq -r "$5" <<< '[]' ;;
  "pr edit")
    [ ! -f "$STUB/fail-edit-$3" ] || { echo 'HTTP 422' >&2; exit 1; } ;;
  *) echo "unexpected gh call: $*" >&2; exit 99 ;;
esac
SH
  chmod +x bin/gh
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export TMPDIR="$BATS_TEST_TMPDIR"
  export GITHUB_REPOSITORY=o/r GH_TOKEN=token PENDING_LABEL='autorelease: pending' BASE_BRANCH=main
  unset REVIEWERS PRS
}

# asked N LOGIN...: the timeline of PR N holds a review request for each LOGIN.
asked() {
  local n="$1"
  shift
  printf '%s\n' "$@" | jq -R '{event: "review_requested", requested_reviewer: {login: .}}' |
    jq -s '. + [{event: "labeled"}, {event: "review_requested", requested_team: {slug: "core"}}]' \
      > "$STUB/timeline-$n.json"
}

edits() { grep '^pr edit' "$STUB/gh.log" || true; }

@test "the PRs release-please touched get a review request from every listed user" {
  REVIEWERS=' octocat , hubot,,' PRS='[{"number":12},{"number":15}]' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(edits)" = "$(printf '%s\n' \
    'pr edit 12 --repo o/r --add-reviewer octocat,hubot' \
    'pr edit 15 --repo o/r --add-reviewer octocat,hubot')" ]
  ! grep -q '^pr list' "$STUB/gh.log"
}

@test "a user already asked, in any case, is skipped; a PR with nobody left gets no edit" {
  asked 12 OctoCat
  asked 15 octocat hubot
  REVIEWERS='octocat,hubot,octocat' PRS='[{"number":12},{"number":15}]' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(edits)" = 'pr edit 12 --repo o/r --add-reviewer hubot' ]
  [[ "$output" == *"ℹ️ octocat was already asked to review PR #12, skipping"* ]]
  [[ "$output" == *"ℹ️ hubot was already asked to review PR #15, skipping"* ]]
}

@test "with no PR from release-please, the open release PR of the base branch is found by its label" {
  printf '21\n' > "$STUB/list"
  REVIEWERS=octocat PRS=null run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qxF 'pr list --repo o/r --label autorelease: pending --state open --base main --json number --jq .[].number' "$STUB/gh.log"
  [ "$(edits)" = 'pr edit 21 --repo o/r --add-reviewer octocat' ]
  rm "$STUB/gh.log"
  REVIEWERS=octocat PRS='' BASE_BRANCH='' run bash "$SCRIPT"
  grep -qxF 'pr list --repo o/r --label autorelease: pending --state open --json number --jq .[].number' "$STUB/gh.log"
}

@test "no open release PR: nothing to notify" {
  REVIEWERS=octocat PRS='[]' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ℹ️ Release PRs to notify: none"* ]]
  [ -z "$(edits)" ]
}

@test "failures warn and never fail the release: the list, a timeline, an edit" {
  touch "$STUB/fail-list"
  REVIEWERS=octocat PRS=null run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::Could not list the open release PRs labelled 'autorelease: pending': HTTP 502"* ]]
  [ -z "$(edits)" ]
  touch "$STUB/fail-timeline-12" "$STUB/fail-edit-15"
  REVIEWERS=octocat PRS='[{"number":12},{"number":15},{"number":16}]' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::Could not read the timeline of PR #12, skipping it: HTTP 404"* ]]
  [[ "$output" == *"::warning::Could not request a review from octocat on PR #15: HTTP 422"* ]]
  [ "$(edits)" = "$(printf '%s\n' \
    'pr edit 15 --repo o/r --add-reviewer octocat' \
    'pr edit 16 --repo o/r --add-reviewer octocat')" ]
}

@test "unusable values warn and are left out, since a failed step would block the alias tags" {
  REVIEWERS='octocat,bad user,-x' PRS='[{"number":12}]' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::notify-reviewers: 'bad user' is not a GitHub login, skipping it"* ]]
  [[ "$output" == *"::warning::notify-reviewers: '-x' is not a GitHub login, skipping it"* ]]
  [ "$(edits)" = 'pr edit 12 --repo o/r --add-reviewer octocat' ]
  rm "$STUB/gh.log"
  printf '21\n' > "$STUB/list"
  REVIEWERS=octocat PRS='not json' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::release-please's prs output is not a JSON array of pull requests: looking the PR up by its label"* ]]
  [ "$(edits)" = 'pr edit 21 --repo o/r --add-reviewer octocat' ]
  rm "$STUB/gh.log"
  REVIEWERS=' , ' PRS='[{"number":12}]' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$STUB/gh.log" ]
}
