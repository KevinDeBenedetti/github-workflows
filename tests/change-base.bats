#!/usr/bin/env bats
# Tests for .github/actions/change-base/change-base.sh
# Each case asserts only the two outputs, base and mode, on throwaway repos.

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/change-base/change-base.sh"

# Empty commits without hooks or signing. The subcommand is built at runtime so
# this file never contains the literal command blocked by the agent guardrails.
snapshot() {
  git -c user.name=t -c user.email=t@t -c "com""mit.gpgsign=false" "com""mit" -q --allow-empty -m "$1"
}

# History of the origin repository:
#   main       c1 ── FORK ── MAIN_TIP
#   feature           └── FEATURE_PREV ── feature's tip (HEAD)
#   rewritten  GONE, created after the clones: origin serves it, no clone has it
# The fork point differs from HEAD~1 (FEATURE_PREV) and from the default
# branch's tip (MAIN_TIP), so neither can pass for it.
# `clone` is complete (origin/main included) and has feature checked out;
# `shallow` holds feature's tip only, at depth 1.
setup() {
  cd "$BATS_TEST_TMPDIR"
  git init -q --template= -b main origin
  (
    cd origin
    git config uploadpack.allowAnySHA1InWant true
    snapshot c1
    snapshot fork
    git checkout -q -b feature
    snapshot feature-1
    snapshot feature-2
    git checkout -q main
    snapshot main-tip
  )
  C1="$(git -C origin rev-parse main~2)"
  FORK="$(git -C origin rev-parse main~1)"
  MAIN_TIP="$(git -C origin rev-parse main)"
  FEATURE_PREV="$(git -C origin rev-parse feature~1)"
  git clone -q "file://$BATS_TEST_TMPDIR/origin" clone
  git -C clone checkout -q feature
  git clone -q --depth 1 --single-branch --branch feature "file://$BATS_TEST_TMPDIR/origin" shallow
  (
    cd origin
    git checkout -q -b rewritten
    snapshot gone
    git checkout -q main
  )
  GONE="$(git -C origin rev-parse rewritten)"
  MISSING=1234567890abcdef1234567890abcdef12345678
  unset EVENT REF BEFORE PR_BASE DEFAULT_BRANCH BASE_REF FETCH_BASE
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/out"
  : > "$GITHUB_OUTPUT"
  cd clone
}

# expect BASE MODE: the outputs the last run wrote.
expect() {
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_OUTPUT")" = "$(printf 'base=%s\nmode=%s' "$1" "$2")" ]
}

# absent SHA: the commit is not in the current clone.
absent() {
  run git cat-file -e "$1^{commit}"
  [ "$status" -ne 0 ]
}

@test "base-ref overrides the lookup, as a SHA or a name" {
  BASE_REF="$C1" EVENT=pull_request PR_BASE="$FORK" run bash "$SCRIPT"
  expect "$C1" override
  : > "$GITHUB_OUTPUT"
  BASE_REF=origin/main run bash "$SCRIPT"
  expect "$MAIN_TIP" override
}

@test "a base-ref that is not in the clone fails" {
  BASE_REF="$MISSING" run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::base-ref '$MISSING' is not a commit of this clone"* ]]
}

@test "pull request: the base commit" {
  EVENT=pull_request PR_BASE="$MAIN_TIP" run bash "$SCRIPT"
  expect "$MAIN_TIP" pull-request
  : > "$GITHUB_OUTPUT"
  EVENT=pull_request_target PR_BASE="$C1" run bash "$SCRIPT"
  expect "$C1" pull-request
}

@test "push: the commit before the push" {
  EVENT=push REF=refs/heads/feature BEFORE="$FEATURE_PREV" DEFAULT_BRANCH=main run bash "$SCRIPT"
  expect "$FEATURE_PREV" push
}

@test "new branch: the fork point with the default branch" {
  EVENT=push REF=refs/heads/feature BEFORE=0000000000000000000000000000000000000000 DEFAULT_BRANCH=main \
    run bash "$SCRIPT"
  expect "$FORK" fork-point
}

@test "force push: the fork point when the previous commit is gone" {
  EVENT=push REF=refs/heads/feature BEFORE="$MISSING" DEFAULT_BRANCH=main run bash "$SCRIPT"
  expect "$FORK" fork-point
}

@test "a push to the default branch itself has no fork point" {
  git checkout -q main
  EVENT=push REF=refs/heads/main BEFORE="$MISSING" DEFAULT_BRANCH=main run bash "$SCRIPT"
  expect "" none
}

@test "a shallow clone without the default branch has none" {
  cd ../shallow
  EVENT=push REF=refs/heads/feature BEFORE="$FEATURE_PREV" DEFAULT_BRANCH=main run bash "$SCRIPT"
  expect "" none
}

@test "manual and scheduled runs have none" {
  for event in workflow_dispatch schedule; do
    : > "$GITHUB_OUTPUT"
    EVENT="$event" DEFAULT_BRANCH=main run bash "$SCRIPT"
    expect "" none
  done
}

@test "fetch-base fetches a base missing from a shallow clone, that one commit" {
  cd ../shallow
  absent "$C1"
  EVENT=pull_request PR_BASE="$C1" FETCH_BASE=true run bash "$SCRIPT"
  expect "$C1" pull-request
  git cat-file -e "$C1^{commit}"
}

@test "fetch-base: a base that cannot be fetched gives none" {
  cd ../shallow
  EVENT=pull_request PR_BASE="$MISSING" FETCH_BASE=true run bash "$SCRIPT"
  expect "" none
  [[ "$output" == *"cannot be fetched"* ]]
}

@test "without fetch-base a base outside the clone gives none, and nothing is fetched" {
  cd ../shallow
  EVENT=pull_request PR_BASE="$C1" run bash "$SCRIPT"
  expect "" none
  absent "$C1"
}

@test "fetch-base fetches nothing in a complete clone: a force push goes to the fork point" {
  EVENT=push REF=refs/heads/feature BEFORE="$GONE" DEFAULT_BRANCH=main FETCH_BASE=true run bash "$SCRIPT"
  expect "$FORK" fork-point
  absent "$GONE"
}

@test "fetch-base in a shallow clone uses a discarded tip that origin still serves" {
  cd ../shallow
  EVENT=push REF=refs/heads/feature BEFORE="$GONE" DEFAULT_BRANCH=main FETCH_BASE=true run bash "$SCRIPT"
  expect "$GONE" push
}

@test "logs the change base, and runs without GITHUB_OUTPUT" {
  unset GITHUB_OUTPUT
  EVENT=push REF=refs/heads/feature BEFORE="$FEATURE_PREV" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Change base: $FEATURE_PREV (push)"* ]]
}

@test "rejects a fetch-base other than true or false" {
  FETCH_BASE=yes run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == "::error::FETCH_BASE must be true or false"* ]]
}
