#!/usr/bin/env bats
# Tests for .github/actions/check-report-inputs/check-report-inputs.sh

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/check-report-inputs/check-report-inputs.sh"

setup() {
  unset S3_ENDPOINT S3_BUCKET S3_PREFIX S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY
  export ARTIFACT_RETENTION_DAYS=7 UPLOAD_ARTIFACT=true
}

# with_s3 [VAR=value...]: run the script with a complete, valid S3 setup.
with_s3() {
  env S3_ENDPOINT=https://s3.eu-central-003.backblazeb2.com S3_BUCKET=perf-reports \
    S3_ACCESS_KEY_ID=key-id-123 S3_SECRET_ACCESS_KEY=secret-key-456 "$@" bash "$SCRIPT"
}

@test "the defaults pass: an artifact for 7 days, no S3 copy" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "Report settings: artifact kept 7 day(s), S3 copy: none." ]
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
  [ "$output" = "Report settings: no artifact, S3 copy: none." ]
  for value in yes 1 '' True; do
    UPLOAD_ARTIFACT="$value" run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"upload-artifact must be true or false (got '$value')"* ]]
  done
}

@test "a complete S3 setup passes and names the bucket and the endpoint, never a credential" {
  UPLOAD_ARTIFACT=false run with_s3 S3_PREFIX=perf/reports
  [ "$status" -eq 0 ]
  [ "$output" = "Report settings: no artifact, S3 copy: s3://perf-reports at https://s3.eu-central-003.backblazeb2.com." ]
  [[ "$output" != *key-id-123* && "$output" != *secret-key-456* ]]
}

@test "with a bucket, both credentials are required, and named without their value" {
  run with_s3 S3_ACCESS_KEY_ID=
  [ "$status" -eq 1 ]
  [ "$output" = "::error::report-s3-bucket is set but the report-s3-access-key-id secret is empty" ]
  run with_s3 S3_SECRET_ACCESS_KEY=
  [ "$status" -eq 1 ]
  [ "$output" = "::error::report-s3-bucket is set but the report-s3-secret-access-key secret is empty" ]
}

@test "the endpoint is the https:// URL of a host, with no path and no credentials" {
  for endpoint in https://s3.us-west-004.backblazeb2.com https://minio.example.com:9000 https://s3.example.com/; do
    run with_s3 S3_ENDPOINT="$endpoint"
    [ "$status" -eq 0 ]
  done
  for endpoint in '' http://s3.example.com s3.example.com https://user:pass@s3.example.com \
    https://s3.example.com/bucket 'https://s3.example.com ' https://-bad.example.com; do
    run with_s3 S3_ENDPOINT="$endpoint"
    [ "$status" -eq 1 ]
    [[ "$output" == *"report-s3-endpoint must be the https:// URL of the S3 API host"* ]]
  done
}

@test "the bucket follows the S3 naming rules" {
  for bucket in abc my-perf.reports Reports-2026; do
    run with_s3 S3_BUCKET="$bucket"
    [ "$status" -eq 0 ]
  done
  for bucket in ab -bucket bucket- 'my bucket' my_bucket "$(printf 'b%.0s' {1..64})"; do
    run with_s3 S3_BUCKET="$bucket"
    [ "$status" -eq 1 ]
    [[ "$output" == *"report-s3-bucket must be 3 to 63 letters, digits, dots or hyphens"* ]]
  done
}

@test "the prefix holds safe key characters, with no . or .. segment" {
  for prefix in perf perf/reports /perf/ a.b-c_d/2026; do
    run with_s3 S3_PREFIX="$prefix"
    [ "$status" -eq 0 ]
  done
  for prefix in ../x a/../b ./x a/. 'a b' 'a?b' 'a*b' $'a\nb'; do
    run with_s3 S3_PREFIX="$prefix"
    [ "$status" -eq 1 ]
    [[ "$output" == *"report-s3-prefix may only hold letters, digits and . _ - /"* ]]
  done
}

@test "S3 settings without a bucket only warn: nothing is copied" {
  S3_ENDPOINT=https://s3.example.com S3_SECRET_ACCESS_KEY=secret-key-456 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::report-s3-bucket is empty: the report is not copied to S3"* ]]
  [[ "$output" != *secret-key-456* ]]
}
