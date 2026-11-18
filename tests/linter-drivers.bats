#!/usr/bin/env bats
# Tests for the scripts of the shellcheck and actionlint actions, with a fake
# linter on PATH that records the arguments of each call.

SHELLCHECK="$BATS_TEST_DIRNAME/../.github/actions/shellcheck/shellcheck.sh"
ACTIONLINT="$BATS_TEST_DIRNAME/../.github/actions/actionlint/actionlint.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p bin calls repo
  export CALLS="$BATS_TEST_TMPDIR/calls"
  # The fake writes call N's arguments, one per line, to calls/N, and exits
  # with the status listed on line N of $FAIL_CALLS (0 when absent).
  local name
  for name in shellcheck actionlint; do
    cat > "bin/$name" << 'SH'
#!/usr/bin/env bash
n=$(( $(ls "$CALLS" | wc -l) + 1 ))
printf '%s\n' "$@" > "$CALLS/$n"
exit "$(sed -n "${n}p" "${FAIL_CALLS:-/dev/null}" 2> /dev/null | grep . || echo 0)"
SH
    chmod +x "bin/$name"
  done
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  unset SEVERITY EXCLUDE_PATHS DEFAULT_SHELL PATHS FLAGS FAIL_CALLS
  cd repo
}

# script FILE FIRST-LINE: a script whose first line is FIRST-LINE.
script() {
  mkdir -p "$(dirname "$1")"
  printf '%s\necho hi\n' "$2" > "$1"
}

# call N: the arguments of the linter's call N, one per line.
call() { cat "$CALLS/$1"; }

@test "shellcheck: each script is checked as the dialect it declares" {
  script a/posix.sh '#!/bin/sh'
  script a/bash.sh '#!/usr/bin/env bash'
  script a/env-s.sh '#!/usr/bin/env -S bash -e'
  script a/busybox.sh '#!/bin/busybox sh'
  script a/directive.sh '# shellcheck shell=dash'
  script b/lib.sh '# a sourced library'
  script b/zsh.sh '#!/usr/bin/env zsh'
  script b/empty.sh '#!'
  run bash "$SHELLCHECK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Checked 8 script(s)."* ]]
  [ "$(call 1)" = "$(printf '%s\n' --severity=warning --format=gcc \
    ./a/bash.sh ./a/busybox.sh ./a/directive.sh ./a/env-s.sh ./a/posix.sh)" ]
  [ "$(call 2)" = "$(printf '%s\n' --severity=warning --shell=bash --format=gcc \
    ./b/empty.sh ./b/lib.sh ./b/zsh.sh)" ]
}

@test "shellcheck: skips .git, node_modules, .venv, non-.sh files and exclude-paths" {
  script keep.sh '#!/bin/sh'
  script .git/hooks/x.sh '#!/bin/sh'
  script web/node_modules/y.sh '#!/bin/sh'
  script .venv/z.sh '#!/bin/sh'
  script tests/test_helper/bats.sh '#!/bin/sh'
  script vendor/other.sh '#!/bin/sh'
  script tool.bash '#!/bin/sh'
  run bash "$SHELLCHECK"
  [ "$status" -eq 0 ]
  [ "$(call 1)" = "$(printf '%s\n' --severity=warning --format=gcc ./keep.sh ./vendor/other.sh)" ]
  rm "$CALLS"/*
  EXCLUDE_PATHS='./vendor/*' run bash "$SHELLCHECK"
  [ "$(call 1)" = "$(printf '%s\n' --severity=warning --format=gcc ./keep.sh ./tests/test_helper/bats.sh)" ]
}

@test "shellcheck: severity and default-shell reach ShellCheck, and a failing pass fails the step" {
  script a.sh '#!/bin/sh'
  script b.sh ''
  printf '1\n0\n' > "$BATS_TEST_TMPDIR/fail"
  SEVERITY=error DEFAULT_SHELL=sh FAIL_CALLS="$BATS_TEST_TMPDIR/fail" run bash "$SHELLCHECK"
  [ "$status" -eq 1 ]
  # The second pass still runs after the first one failed.
  [ "$(call 2)" = "$(printf '%s\n' --severity=error --shell=sh --format=gcc ./b.sh)" ]
  [[ "$output" == *"Checked 2 script(s)."* ]]
}

@test "shellcheck: no script, no call; unusable settings fail" {
  run bash "$SHELLCHECK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Checked 0 script(s)."* ]]
  [ -z "$(ls "$CALLS")" ]
  SEVERITY=warn run bash "$SHELLCHECK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::severity must be error, warning, info or style, not 'warn'"* ]]
  DEFAULT_SHELL=zsh run bash "$SHELLCHECK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::default-shell must be sh, bash, dash, ksh or busybox, not 'zsh'"* ]]
}

@test "actionlint: quoted flags reach actionlint as one argument each, without their quotes" {
  script .github/workflows/ci.yml 'on: push'
  FLAGS="-ignore 'SC2086' -ignore \"needs a b\" -shellcheck=" run bash "$ACTIONLINT"
  [ "$status" -eq 0 ]
  [ "$(call 1)" = "$(printf '%s\n' -ignore SC2086 -ignore 'needs a b' -shellcheck= .github/workflows/ci.yml)" ]
  rm "$CALLS"/*
  FLAGS='-ignore create-github-app-token' run bash "$ACTIONLINT"
  [ "$(call 1)" = "$(printf '%s\n' -ignore create-github-app-token .github/workflows/ci.yml)" ]
}

@test "actionlint: an unmatched quote in flags fails before actionlint runs" {
  script .github/workflows/ci.yml 'on: push'
  FLAGS="-ignore 'SC2086" run bash "$ACTIONLINT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::actionlint flags must be a shell command line"* ]]
  [ -z "$(ls "$CALLS")" ]
}

@test "actionlint: directories, files and globs give every workflow once per match" {
  script .github/workflows/a.yml 'on: push'
  script .github/workflows/sub/b.yaml 'on: push'
  script .github/workflows/notes.md '# not a workflow'
  script ci/c.yml 'on: push'
  script ci/d.yml 'on: push'
  run bash "$ACTIONLINT"
  [ "$status" -eq 0 ]
  [ "$(call 1)" = "$(printf '%s\n' .github/workflows/a.yml .github/workflows/sub/b.yaml)" ]
  rm "$CALLS"/*
  PATHS='ci/c.yml ci/d*.yml' run bash "$ACTIONLINT"
  [ "$status" -eq 0 ]
  [ "$(call 1)" = "$(printf '%s\n' ci/c.yml ci/d.yml)" ]
}

@test "actionlint: a paths entry that matches nothing fails, so a typo cannot skip the check" {
  script .github/workflows/a.yml 'on: push'
  PATHS='.github/workflows/ .github/workflow/' run bash "$ACTIONLINT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::paths entry '.github/workflow/' matches no file or directory"* ]]
  PATHS='ci/*.yml' run bash "$ACTIONLINT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::paths entry 'ci/*.yml' matches no file or directory"* ]]
  mkdir empty
  PATHS=empty run bash "$ACTIONLINT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::no workflow file under 'empty'"* ]]
  PATHS=' ' run bash "$ACTIONLINT"
  [ "$status" -eq 1 ]
  [ -z "$(ls "$CALLS")" ]
}

@test "actionlint: its exit status is the step's" {
  script .github/workflows/a.yml 'on: push'
  echo 1 > "$BATS_TEST_TMPDIR/fail"
  FAIL_CALLS="$BATS_TEST_TMPDIR/fail" run bash "$ACTIONLINT"
  [ "$status" -eq 1 ]
}
