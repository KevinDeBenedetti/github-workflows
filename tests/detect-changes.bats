#!/usr/bin/env bats
# Tests for .github/actions/detect-changes/detect-changes.sh
# The change base comes from the change-base action (tests/change-base.bats);
# here it is set directly.

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/detect-changes/detect-changes.sh"

# Throwaway repo without hooks or signing. The subcommand is built at runtime so
# this file never contains the literal command blocked by the agent guardrails.
snapshot() {
  git add -A
  git -c user.name=t -c user.email=t@t -c "com""mit.gpgsign=false" "com""mit" -q -m "$1"
}

setup() {
  cd "$BATS_TEST_TMPDIR"
  git init -q --template= .
  mkdir -p apps/api apps/web apps/My-App
  for app in api web My-App; do printf '%s\n' "$app" > "apps/$app/main.txt"; done
  snapshot base
  BASE_SHA="$(git rev-parse HEAD)"
  printf 'v2\n' >> apps/api/main.txt
  snapshot change
  unset APPS_DIR BASE
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/out"
  : > "$GITHUB_OUTPUT"
}

# output_of KEY: the value the last run wrote for KEY.
output_of() { sed -n "s/^$1=//p" "$GITHUB_OUTPUT"; }

@test "lists the apps changed since the change base" {
  BASE="$BASE_SHA" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_of changed_apps)" = '["api"]' ]
  [ "$(output_of has_changes)" = true ]
  [ "$(output_of changed_api)" = true ]
  [ "$(output_of changed_web)" = false ]
}

@test "no app changed since the change base" {
  BASE="$(git rev-parse HEAD)" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_of changed_apps)" = '[]' ]
  [ "$(output_of has_changes)" = false ]
}

@test "no change base: every app counts as changed, with a warning" {
  BASE='' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::No change base for this run"* ]]
  [ "$(output_of changed_apps | jq -c sort)" = '["My-App","api","web"]' ]
  [ "$(output_of has_changes)" = true ]
}

@test "a change base missing from the clone fails" {
  BASE=1234567890abcdef1234567890abcdef12345678 run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::Change base 1234567890abcdef1234567890abcdef12345678 is not in the clone."* ]]
  [ ! -s "$GITHUB_OUTPUT" ]
}

@test "a missing apps directory gives no app" {
  APPS_DIR=services BASE="$BASE_SHA" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Directory 'services' not found"* ]]
  [ "$(output_of changed_apps)" = '[]' ]
  [ "$(output_of has_changes)" = false ]
}

@test "per-app keys are lowercased and sanitised, names are kept" {
  printf 'v2\n' >> apps/My-App/main.txt
  snapshot again
  APPS_DIR=apps/ BASE="$BASE_SHA" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_of changed_my_app)" = true ]
  [ "$(output_of changed_apps | jq -c sort)" = '["My-App","api"]' ]
}
