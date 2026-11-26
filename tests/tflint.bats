#!/usr/bin/env bats
# Tests for .github/actions/tflint/tflint.sh, with a fake tflint on PATH that
# logs each call's arguments on one line.

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/tflint/tflint.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p bin terraform
  export LOG="$BATS_TEST_TMPDIR/calls.log"
  cat > bin/tflint << 'SH'
#!/usr/bin/env bash
echo "$*" >> "$LOG"
case " $* " in
  *" --init "*) exit "${FAKE_INIT_EXIT:-0}" ;;
esac
[ "${FAKE_EXIT:-0}" -eq 0 ] || echo "main.tf:3:1: Warning - variable \"unused\" is declared but not used (terraform_unused_declarations)"
exit "${FAKE_EXIT:-0}"
SH
  chmod +x bin/tflint
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export TF_DIR=terraform
}

@test "installs the plugins of the module's .tflint.hcl, then lints the module" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = "$(printf '%s\n' '--chdir=terraform --init' '--chdir=terraform --format=compact')" ]
}

@test "an issue fails the step with tflint's exit code and shows the issue" {
  FAKE_EXIT=2 run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"terraform_unused_declarations"* ]]
}

@test "a plugin that cannot be installed fails before linting" {
  FAKE_INIT_EXIT=1 run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [ "$(wc -l < "$LOG")" -eq 1 ]
}

@test "a directory that does not exist is an error" {
  TF_DIR=nope run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::tflint: directory not found: nope"* ]]
  [ ! -e "$LOG" ]
}
