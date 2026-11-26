#!/usr/bin/env bats
# Tests for .github/actions/config-scan/config-scan.sh, with a fake trivy on
# PATH: it logs each call's arguments on one line, and `trivy config` writes
# the report of $FAKE_REPORT to its --output file.

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/config-scan/config-scan.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p bin terraform runner
  export LOG="$BATS_TEST_TMPDIR/calls.log" RUNNER_TEMP="$BATS_TEST_TMPDIR/runner"
  export FAKE_REPORT="$BATS_TEST_TMPDIR/report.json"
  cat > bin/trivy << 'SH'
#!/usr/bin/env bash
echo "$*" >> "$LOG"
[ "${FAKE_EXIT:-0}" -eq 0 ] || exit "$FAKE_EXIT"
out=''
while [ $# -gt 0 ]; do
  [ "$1" = --output ] && out="$2"
  shift
done
case "$out" in
  *.json) cp "$FAKE_REPORT" "$out" ;;
  *) echo sarif > "$out" ;;
esac
SH
  chmod +x bin/trivy
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export SCAN_PATH=terraform FAIL_ON=high REPORT_PATH=''
  echo '{"Results": [{"Target": ".", "Class": "config"}]}' > "$FAKE_REPORT"
}

# One finding, as trivy 0.76 reports it.
finding() {
  cat > "$FAKE_REPORT" << 'JSON'
{"Results": [{"Target": "main.tf", "Class": "config", "Type": "terraform", "Misconfigurations": [
  {"ID": "AWS-0107", "Severity": "HIGH",
   "Title": "Security groups should not allow unrestricted ingress to SSH or RDP from any IP address.",
   "PrimaryURL": "https://avd.aquasec.com/misconfig/aws-0107",
   "CauseMetadata": {"StartLine": 6, "EndLine": 6}}
]}]}
JSON
}

@test "a clean directory passes, scanned at the threshold and above" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No misconfiguration at high or above in terraform"* ]]
  [ "$(cat "$LOG")" = "config --quiet --severity HIGH,CRITICAL --format json --output $RUNNER_TEMP/config-scan.json terraform" ]
}

@test "a finding fails the step, with an annotation on its file and line" {
  finding
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error file=terraform/main.tf,line=6,title=AWS-0107 (HIGH)::Security groups should not allow unrestricted ingress to SSH or RDP from any IP address. https://avd.aquasec.com/misconfig/aws-0107"* ]]
  [[ "$output" == *"1 misconfiguration(s) at high or above in terraform"* ]]
}

@test "fail-on picks the severities trivy reports" {
  FAIL_ON=critical run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q -- '--severity CRITICAL ' "$LOG"
  FAIL_ON=low run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q -- '--severity LOW,MEDIUM,HIGH,CRITICAL ' "$LOG"
  FAIL_ON=everything run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::config-scan: fail-on must be low, medium, high or critical (got 'everything')"* ]]
}

@test "a report path gets the SARIF conversion, findings or not" {
  finding
  REPORT_PATH=out.sarif run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [ "$(tail -n 1 "$LOG")" = "convert --quiet --format sarif --output out.sarif $RUNNER_TEMP/config-scan.json" ]
  [ -f out.sarif ]
}

@test "a scan that cannot run fails with trivy's exit code, and a missing directory is an error" {
  FAKE_EXIT=3 run bash "$SCRIPT"
  [ "$status" -eq 3 ]
  SCAN_PATH=nope run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::config-scan: directory not found: nope"* ]]
}
