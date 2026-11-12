#!/usr/bin/env bats
# Tests for .github/actions/check-report-inputs/check-report-inputs.sh

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/check-report-inputs/check-report-inputs.sh"

setup() {
  export ARTIFACT_RETENTION_DAYS=7 UPLOAD_ARTIFACT=true
}

@test "the defaults pass: an artifact for 7 days" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "Report settings: artifact kept 7 day(s)." ]
}

@test "artifact-retention-days is a whole number from 1 to 90" {
  for days in 1 07 90; do
    ARTIFACT_RETENTION_DAYS="$days" run bash "$SCRIPT"
    [ "$status" -eq 0 ]
  done
  for days in 0 00 91 100 -1 7.5 abc '' ' 7' 1e1 2147483655; do
    ARTIFACT_RETENTION_DAYS="$days" run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [ "$output" = "::error::artifact-retention-days must be a whole number from 1 to 90 (got '$days')" ]
  done
}

@test "upload-artifact is true or false" {
  UPLOAD_ARTIFACT=false run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "Report settings: no artifact." ]
  for value in yes 1 '' True; do
    UPLOAD_ARTIFACT="$value" run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"upload-artifact must be true or false (got '$value')"* ]]
  done
}
