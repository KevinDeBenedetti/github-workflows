#!/usr/bin/env bats
# Tests for .github/actions/upload-report-s3/upload-report-s3.sh

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/upload-report-s3/upload-report-s3.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p bin tmp stub report/sub
  printf '<html></html>\n' > report/index.html
  printf '{}\n' > report/sub/data.json
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export STUB_DIR="$BATS_TEST_TMPDIR/stub" TMPDIR="$BATS_TEST_TMPDIR/tmp" RUNNER_TEMP="$BATS_TEST_TMPDIR/tmp"
  # The package the fake download serves, pinned by its real SHA-256: the
  # check the script runs is the real one.
  printf 'not really rclone\n' > "$STUB_DIR/rclone.deb"
  local hash
  hash="$(sha256sum "$STUB_DIR/rclone.deb" | cut -d' ' -f1)"
  export RCLONE_VERSION=1.75.2 RCLONE_SHA256_amd64="$hash" RCLONE_SHA256_arm64="$hash"
  export REPORT_DIR=report REPORT_NAME=sitespeed-result-desktop REPORT_WORKFLOW=perf-sitespeed
  export S3_ENDPOINT=https://s3.eu-central-003.backblazeb2.com S3_BUCKET=perf-reports S3_PREFIX=perf
  export S3_ACCESS_KEY_ID=key-id-123 S3_SECRET_ACCESS_KEY=secret-key-456
  export GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=42 GITHUB_RUN_ATTEMPT=2
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md" GITHUB_OUTPUT="$BATS_TEST_TMPDIR/output"
  unset STUB_ARCH
  stub_tools
}

# refute CMD...: fails the test when CMD succeeds (a bare `! CMD` never does).
refute() {
  if "$@"; then
    echo "unexpected success: $*" >&2
    return 1
  fi
}

# Fakes for what the script runs:
#   uname -m          prints $STUB_ARCH (default x86_64)
#   curl, wget        log their arguments, then serve rclone.deb into the -o or
#                     -O file
#   dpkg-deb -x       unpacks a fake rclone that logs its arguments
#                     (rclone-args.log) and its RCLONE_* environment
#                     (rclone-env.log), and exits with rclone-exit (default 0)
stub_tools() {
  cat > bin/uname <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = -m ]; then echo "${STUB_ARCH:-x86_64}"; else echo Linux; fi
EOF
  cat > bin/curl <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/curl.log"
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cp "$STUB_DIR/rclone.deb" "$out"
EOF
  cat > bin/wget <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/wget.log"
while [ $# -gt 0 ]; do
  case "$1" in
    -O) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cp "$STUB_DIR/rclone.deb" "$out"
EOF
  cat > bin/dpkg-deb <<'EOF'
#!/usr/bin/env bash
[ "$1" = -x ] || exit 2
mkdir -p "$3/usr/bin"
cat > "$3/usr/bin/rclone" <<'RCLONE'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$STUB_DIR/rclone-args.log"
env | grep '^RCLONE_' | sort > "$STUB_DIR/rclone-env.log"
if [ -s "$RCLONE_CONFIG" ]; then echo 'config file: not empty'; else echo 'config file: empty'; fi >> "$STUB_DIR/rclone-env.log"
exit "$(cat "$STUB_DIR/rclone-exit" 2> /dev/null || echo 0)"
RCLONE
chmod +x "$3/usr/bin/rclone"
EOF
  chmod +x bin/uname bin/curl bin/wget bin/dpkg-deb
}

destination=perf-reports/perf/o/r/perf-sitespeed/42-2/sitespeed-result-desktop

@test "copies the report under <prefix>/<owner>/<repo>/<workflow>/<run>-<attempt>/<name> and says where" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB_DIR/rclone-args.log")" = "copy report report:$destination --no-check-dest --stats 0 --log-level NOTICE" ]
  grep -qx "path=s3://$destination/" output
  grep -qF "\`s3://$destination/\` on https://s3.eu-central-003.backblazeb2.com: 2 file(s)" summary.md
  [[ "$output" == *"Copied to s3://$destination/"* ]]
}

@test "the credentials reach rclone through its environment only, never its arguments or a log" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qx 'RCLONE_CONFIG_REPORT_ACCESS_KEY_ID=key-id-123' "$STUB_DIR/rclone-env.log"
  grep -qx 'RCLONE_CONFIG_REPORT_SECRET_ACCESS_KEY=secret-key-456' "$STUB_DIR/rclone-env.log"
  refute grep -q -e key-id-123 -e secret-key-456 "$STUB_DIR/rclone-args.log" "$STUB_DIR/curl.log" summary.md output
  [[ "$output" != *key-id-123* && "$output" != *secret-key-456* ]]
}

@test "the remote is an S3-compatible service set for a write-only key, from an empty config file" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  for line in RCLONE_CONFIG_REPORT_TYPE=s3 RCLONE_CONFIG_REPORT_PROVIDER=Other \
    RCLONE_CONFIG_REPORT_ENDPOINT=https://s3.eu-central-003.backblazeb2.com \
    RCLONE_CONFIG_REPORT_ENV_AUTH=false RCLONE_CONFIG_REPORT_NO_CHECK_BUCKET=true \
    RCLONE_CONFIG_REPORT_NO_HEAD=true 'config file: empty'; do
    grep -qxF "$line" "$STUB_DIR/rclone-env.log"
  done
}

@test "the region comes from a Backblaze B2 or AWS endpoint, and stays blank otherwise" {
  for pair in https://s3.eu-central-003.backblazeb2.com=eu-central-003 https://s3.us-west-2.amazonaws.com=us-west-2 \
    https://minio.example.com:9000= https://s3.example.com/=; do
    S3_ENDPOINT="${pair%=*}" run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -qx "RCLONE_CONFIG_REPORT_REGION=${pair##*=}" "$STUB_DIR/rclone-env.log"
  done
  # A trailing slash does not reach rclone.
  grep -qx 'RCLONE_CONFIG_REPORT_ENDPOINT=https://s3.example.com' "$STUB_DIR/rclone-env.log"
}

@test "rclone is fetched at the pinned version for the runner's architecture" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qF 'https://github.com/rclone/rclone/releases/download/v1.75.2/rclone-v1.75.2-linux-amd64.deb' "$STUB_DIR/curl.log"
  STUB_ARCH=aarch64 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qF 'rclone-v1.75.2-linux-arm64.deb' "$STUB_DIR/curl.log"
  STUB_ARCH=riscv64 run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::rclone: unsupported architecture riscv64"* ]]
}

@test "a download that does not match its pinned SHA-256 stops before rclone runs" {
  RCLONE_SHA256_amd64="$(printf '0%.0s' {1..64})" run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::rclone 1.75.2 (amd64) does not match its pinned SHA-256"* ]]
  [ ! -e "$STUB_DIR/rclone-args.log" ]
}

@test "without curl, as in the sitespeed.io image, wget downloads rclone" {
  # A PATH of the fakes and of the system tools the script needs, curl left out.
  mkdir sysbin
  for tool in bash cat chmod cp cut du env find grep mkdir mktemp rm sha256sum sort tr wc; do
    ln -s "$(command -v "$tool")" "sysbin/$tool"
  done
  rm bin/curl
  PATH="$BATS_TEST_TMPDIR/bin:$BATS_TEST_TMPDIR/sysbin" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qF 'rclone-v1.75.2-linux-amd64.deb' "$STUB_DIR/wget.log"
  [ ! -e "$STUB_DIR/curl.log" ]
  [ -e "$STUB_DIR/rclone-args.log" ]
}

@test "no report directory: a warning, nothing downloaded or copied" {
  REPORT_DIR=nowhere run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::nowhere is not a directory: no report to copy to S3"* ]]
  [ ! -e "$STUB_DIR/curl.log" ]
  [ ! -e "$STUB_DIR/rclone-args.log" ]
}

@test "a failed copy fails the step and names the destination" {
  echo 7 > "$STUB_DIR/rclone-exit"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::rclone could not copy report to s3://$destination/"* ]]
  refute grep -q path= output
}

@test "the prefix may be empty, and loses its leading, trailing and doubled slashes" {
  S3_PREFIX='' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qx 'path=s3://perf-reports/o/r/perf-sitespeed/42-2/sitespeed-result-desktop/' output
  S3_PREFIX=//a//b/ run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qx 'path=s3://perf-reports/a/b/o/r/perf-sitespeed/42-2/sitespeed-result-desktop/' output
}

@test "invalid settings are refused before any download" {
  for setting in S3_BUCKET=a S3_ENDPOINT=http://s3.example.com S3_PREFIX=../x REPORT_NAME=../x REPORT_NAME= \
    REPORT_WORKFLOW=Perf S3_ACCESS_KEY_ID= S3_SECRET_ACCESS_KEY= GITHUB_REPOSITORY=o GITHUB_RUN_ID=x \
    RCLONE_VERSION=latest RCLONE_SHA256_amd64=abc; do
    run env "$setting" bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::"* ]]
  done
  [ ! -e "$STUB_DIR/curl.log" ]
}
