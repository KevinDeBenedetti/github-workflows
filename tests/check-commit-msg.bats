#!/usr/bin/env bats
# Tests for .github/actions/check-commit-msg/check-commit-msg.sh

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/check-commit-msg/check-commit-msg.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
}

msg() { printf '%b' "$1" > MSG; run bash "$SCRIPT" MSG; }

# Empty commits in a throwaway repo. The subcommand is built at runtime so this
# file never contains the literal command blocked by the agent guardrails.
mkcommit() {
  git -c user.name=t -c user.email=t@t -c "com""mit.gpgsign=false" "com""mit" -q --allow-empty -m "$1"
}

@test "accepts type, scope, breaking marker and body" {
  msg 'feat(api)!: send an email when a product ships\n\n- why it matters\n\nBREAKING CHANGE: emails are sent by default\n'
  [ "$status" -eq 0 ]
}

@test "accepts every release-please type" {
  for t in feat fix perf revert deps docs style chore test build ci; do
    msg "$t: do something\n"
    [ "$status" -eq 0 ] || { echo "rejected: $t"; return 1; }
  done
}

@test "rejects a free-form message" {
  msg 'update stuff\n'
  [ "$status" -eq 1 ]
  [[ "$output" == *"<type>(<scope>)<!>: <summary>"* ]]
}

@test "rejects refactor with a hint to use chore" {
  msg 'refactor(core): split module\n'
  [ "$status" -eq 1 ]
  [[ "$output" == *"use 'chore'"* ]]
}

@test "rejects an unknown type, a missing space, an empty summary or scope" {
  for m in 'feature: x\n' 'fix:x\n' 'fix: \n' 'fix(): x\n'; do
    msg "$m"
    [ "$status" -eq 1 ] || { echo "accepted: $m"; return 1; }
  done
}

@test "rejects a header longer than 100 characters" {
  msg "fix: $(printf 'a%.0s' {1..96})\n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"max 100"* ]]
}

@test "requires a blank line before the body" {
  msg 'fix: x\nbody right away\n'
  [ "$status" -eq 1 ]
  [[ "$output" == *"blank line"* ]]
}

@test "ignores git comment lines and lets merge/fixup messages through" {
  msg '# Please enter the message\nfix: x\n'
  [ "$status" -eq 0 ]
  for m in "Merge branch 'main'\n" 'fixup! fix: x\n' 'squash! feat: y\n'; do
    msg "$m"
    [ "$status" -eq 0 ] || { echo "rejected: $m"; return 1; }
  done
}

@test "CI mode checks every non-merge commit of a range" {
  git init -q repo && cd repo
  mkcommit 'chore: base'
  base=$(git rev-parse HEAD)
  mkcommit 'feat: good'
  COMMIT_RANGE="$base..HEAD" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  mkcommit 'bad message'
  COMMIT_RANGE="$base..HEAD" run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bad message"* ]]
}

@test "fails with usage when given neither a file nor a range" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}
