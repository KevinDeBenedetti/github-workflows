#!/usr/bin/env bats
# Tests for .github/actions/osv-scan/osv-scan.sh, with a fake osv-scanner on
# PATH that logs its arguments on one line and exits with $FAKE_EXIT.

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/osv-scan/osv-scan.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p bin app
  export LOG="$BATS_TEST_TMPDIR/calls.log"
  cat > bin/osv-scanner << 'SH'
#!/usr/bin/env bash
echo "$*" >> "$LOG"
exit "${FAKE_EXIT:-0}"
SH
  chmod +x bin/osv-scanner
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export SCAN_PATH=.
}

@test "every lockfile under the path is audited, recursively" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = "scan source --recursive ." ]
  [[ "$output" == *"No known vulnerability in the dependencies under ."* ]]
}

@test "a vulnerable dependency fails the step" {
  FAKE_EXIT=1 SCAN_PATH=app run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::osv-scan: known vulnerabilities in the dependencies under app"* ]]
}

@test "a checkout without any lockfile passes with a notice" {
  FAKE_EXIT=128 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::notice::osv-scan: no lockfile or manifest found under ."* ]]
}

@test "a scan that could not run fails with the scanner's exit code" {
  FAKE_EXIT=129 run bash "$SCRIPT"
  [ "$status" -eq 129 ]
  [[ "$output" == *"::error::osv-scan: osv-scanner could not complete the scan (exit 129)"* ]]
  SCAN_PATH=nope run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::osv-scan: directory not found: nope"* ]]
}
