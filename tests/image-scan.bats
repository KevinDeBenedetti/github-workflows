#!/usr/bin/env bats
# Tests for .github/actions/image-scan/image-scan.sh, with a fake trivy on
# PATH: it logs its arguments on one line and writes the report of
# $FAKE_REPORT to its --output file.

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/image-scan/image-scan.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p bin runner
  export LOG="$BATS_TEST_TMPDIR/calls.log" RUNNER_TEMP="$BATS_TEST_TMPDIR/runner"
  export FAKE_REPORT="$BATS_TEST_TMPDIR/report.json" GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md"
  cat > bin/trivy << 'SH'
#!/usr/bin/env bash
echo "$*" >> "$LOG"
[ "${FAKE_EXIT:-0}" -eq 0 ] || exit "$FAKE_EXIT"
while [ $# -gt 0 ]; do
  [ "$1" = --output ] && cp "$FAKE_REPORT" "$2"
  shift
done
SH
  chmod +x bin/trivy
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export IMAGE=ghcr.io/acme/api:scan FAIL_ON=critical
  echo '{"Results": [{"Target": "ghcr.io/acme/api:scan (alpine 3.20.1)", "Class": "os-pkgs"}]}' > "$FAKE_REPORT"
  : > "$GITHUB_STEP_SUMMARY"
}

# An image on a base with one critical vulnerability that has a fix and one
# without, as trivy reports them.
vulnerable() {
  cat > "$FAKE_REPORT" << 'JSON'
{"Results": [{"Target": "ghcr.io/acme/api:scan (alpine 3.12.0)", "Class": "os-pkgs", "Type": "alpine", "Vulnerabilities": [
  {"VulnerabilityID": "CVE-2021-36159", "PkgName": "apk-tools", "InstalledVersion": "2.10.5-r1", "FixedVersion": "2.10.7-r0",
   "Severity": "CRITICAL", "Title": "libfetch: an out of boundary read", "PrimaryURL": "https://avd.aquasec.com/nvd/cve-2021-36159"},
  {"VulnerabilityID": "CVE-2099-0001", "PkgName": "zlib", "InstalledVersion": "1.2.11-r3",
   "Severity": "CRITICAL", "Title": "no fix | yet", "PrimaryURL": "https://example.com/cve-2099-0001"}
]}]}
JSON
}

@test "a clean image passes, scanned for vulnerabilities at the threshold and above" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No vulnerability at critical or above in ghcr.io/acme/api:scan"* ]]
  [ "$(cat "$LOG")" = "image --quiet --scanners vuln --severity CRITICAL --format json --output $RUNNER_TEMP/image-scan.json ghcr.io/acme/api:scan" ]
  grep -q 'No vulnerability at `critical` or above' "$GITHUB_STEP_SUMMARY"
}

@test "a vulnerable base image fails the step and lists each finding in the job summary" {
  vulnerable
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"2 vulnerabilities at critical or above in ghcr.io/acme/api:scan"* ]]
  grep -qF '| `apk-tools` | [CVE-2021-36159](https://avd.aquasec.com/nvd/cve-2021-36159) | CRITICAL | 2.10.5-r1 | 2.10.7-r0 | libfetch: an out of boundary read |' "$GITHUB_STEP_SUMMARY"
  # No fix yet: an empty cell; a pipe in a title does not break the table.
  grep -qF '| `zlib` | [CVE-2099-0001](https://example.com/cve-2099-0001) | CRITICAL | 1.2.11-r3 |  | no fix \| yet |' "$GITHUB_STEP_SUMMARY"
}

@test "fail-on picks the severities trivy reports" {
  FAIL_ON=high run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q -- '--severity HIGH,CRITICAL ' "$LOG"
  FAIL_ON=none run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::image-scan: fail-on must be low, medium, high or critical (got 'none')"* ]]
}

@test "a scan that cannot run fails with trivy's exit code, and an image is required" {
  FAKE_EXIT=4 run bash "$SCRIPT"
  [ "$status" -eq 4 ]
  IMAGE='' run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::image-scan: no image to scan"* ]]
}
