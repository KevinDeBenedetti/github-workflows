#!/usr/bin/env bats
# Tests for .github/actions/setup-promtool/setup-promtool.sh. curl is a fake
# that serves each release URL from a local tree (dist/<URL path>) and logs
# it; uname answers the architecture under test. sha256sum and tar are real.

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/setup-promtool/setup-promtool.sh"
PROM_BASE=prometheus/prometheus/releases/download/v3.0.0
YQ_BASE=mikefarah/yq/releases/download/v4.0.0

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

# release ARCH: the Prometheus tarball and the yq binary of ARCH, with the
# checksum files of both releases listing every architecture.
release() {
  local arch="$1" dir="stage/prometheus-3.0.0.linux-$1"
  mkdir -p "$dir" "dist/$PROM_BASE" "dist/$YQ_BASE"
  printf '#!/bin/sh\necho "promtool %s"\n' "$arch" > "$dir/promtool"
  chmod +x "$dir/promtool"
  tar -czf "dist/$PROM_BASE/prometheus-3.0.0.linux-$arch.tar.gz" -C stage "prometheus-3.0.0.linux-$arch"
  printf '#!/bin/sh\necho "yq %s"\n' "$arch" > "dist/$YQ_BASE/yq_linux_$arch"
  printf '%s  %s\n' "$(sha "dist/$PROM_BASE/prometheus-3.0.0.linux-$arch.tar.gz")" \
    "prometheus-3.0.0.linux-$arch.tar.gz" >> "dist/$PROM_BASE/sha256sums.txt"
  # yq's layout: the name, then one column per hash of checksums_hashes_order.
  # SHA-256 is the third hash: a wrong column reads another, wrong, value.
  printf '%s %s %s %s %s\n' "yq_linux_$arch" "$(printf 'a%.0s' {1..32})" "$(printf 'b%.0s' {1..40})" \
    "$(sha "dist/$YQ_BASE/yq_linux_$arch")" "$(printf 'c%.0s' {1..64})" >> "dist/$YQ_BASE/checksums"
}

setup() {
  cd "$BATS_TEST_TMPDIR"
  export RUNNER_TEMP="$BATS_TEST_TMPDIR/runner" GITHUB_PATH="$BATS_TEST_TMPDIR/github-path"
  export PROMTOOL_VERSION=3.0.0 YQ_VERSION=v4.0.0 MACHINE=x86_64
  export DIST="$BATS_TEST_TMPDIR/dist" CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
  mkdir -p "$RUNNER_TEMP" bin
  : > "$GITHUB_PATH"
  printf '#!/bin/sh\necho "$MACHINE"\n' > bin/uname
  # curl … -o FILE URL: copies dist/<URL path> to FILE, fails like curl -f
  # (exit 22) when it is not there.
  cat > bin/curl << 'SH'
#!/bin/sh
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) url="$1"; shift ;;
  esac
done
echo "$url" >> "$CURL_LOG"
src="$DIST/${url#https://github.com/}"
[ -f "$src" ] || { echo "curl: (22) 404 $url" >&2; exit 22; }
cp "$src" "$out"
SH
  chmod +x bin/uname bin/curl
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  release amd64
  release arm64
  mkdir -p "dist/$YQ_BASE"
  printf '%s\n' MD5 SHA-1 SHA-256 SHA-512 > "dist/$YQ_BASE/checksums_hashes_order"
}

@test "installs promtool and yq of the runner's architecture, verified, and adds them to PATH" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_PATH")" = "$RUNNER_TEMP/bin" ]
  [ "$("$RUNNER_TEMP/bin/promtool")" = "promtool amd64" ]
  [ "$("$RUNNER_TEMP/bin/yq")" = "yq amd64" ]
  [ -x "$RUNNER_TEMP/bin/yq" ]
}

@test "downloads each asset and checksum list from its own release" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$CURL_LOG")" = "$(printf '%s\n' \
    "https://github.com/$PROM_BASE/prometheus-3.0.0.linux-amd64.tar.gz" \
    "https://github.com/$PROM_BASE/sha256sums.txt" \
    "https://github.com/$YQ_BASE/yq_linux_amd64" \
    "https://github.com/$YQ_BASE/checksums" \
    "https://github.com/$YQ_BASE/checksums_hashes_order")" ]
}

@test "an arm64 runner gets the arm64 assets" {
  MACHINE=aarch64 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$("$RUNNER_TEMP/bin/promtool")" = "promtool arm64" ]
  [ "$("$RUNNER_TEMP/bin/yq")" = "yq arm64" ]
}

@test "an unsupported architecture fails before any download" {
  MACHINE=riscv64 run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::unsupported arch: riscv64"* ]]
  [ ! -e "$CURL_LOG" ]
}

@test "a Prometheus tarball that does not match its SHA-256 fails, nothing installed" {
  echo tampered >> "dist/$PROM_BASE/prometheus-3.0.0.linux-amd64.tar.gz"
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [ ! -e "$RUNNER_TEMP/bin/promtool" ]
  [ ! -s "$GITHUB_PATH" ]
}

@test "a Prometheus tarball missing from sha256sums.txt fails with its name" {
  grep -v linux-amd64 "dist/$PROM_BASE/sha256sums.txt" > sums && mv sums "dist/$PROM_BASE/sha256sums.txt"
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no SHA-256 for prometheus-3.0.0.linux-amd64.tar.gz in sha256sums.txt"* ]]
}

@test "a yq binary that does not match its SHA-256 column fails, yq not installed" {
  echo tampered >> "dist/$YQ_BASE/yq_linux_amd64"
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [ ! -e "$RUNNER_TEMP/bin/yq" ]
  [ ! -s "$GITHUB_PATH" ]
}

@test "the yq SHA-256 column follows checksums_hashes_order" {
  # Move SHA-256 to the fourth hash: the third column (another hash) must
  # no longer be read as SHA-256.
  printf '%s\n' MD5 SHA-1 SHA-512 SHA-256 > "dist/$YQ_BASE/checksums_hashes_order"
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [ ! -e "$RUNNER_TEMP/bin/yq" ]
}

@test "SHA-256 missing from checksums_hashes_order fails with the existing message" {
  printf '%s\n' MD5 SHA-1 > "dist/$YQ_BASE/checksums_hashes_order"
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SHA-256 not listed in checksums_hashes_order"* ]]
}

@test "a yq binary missing from checksums fails with its name" {
  grep -v yq_linux_amd64 "dist/$YQ_BASE/checksums" > sums && mv sums "dist/$YQ_BASE/checksums"
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no SHA-256 for yq_linux_amd64 in checksums"* ]]
}

@test "a missing release asset fails the step" {
  rm "dist/$YQ_BASE/yq_linux_amd64"
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"404"* ]]
}
