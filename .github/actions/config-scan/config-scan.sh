#!/usr/bin/env bash
# Scan the infrastructure-as-code files under SCAN_PATH for misconfigurations
# with `trivy config` (Terraform, Kubernetes manifests, Helm charts,
# Dockerfiles, …: trivy picks the scanner per file).
#
# Each finding at FAIL_ON or above becomes an error annotation on its file and
# line, and fails the step. With REPORT_PATH, the same findings are also
# written there as SARIF, findings or not.
#
# Env: SCAN_PATH     directory to scan
#      FAIL_ON       lowest severity that fails: low, medium, high or critical
#      REPORT_PATH   SARIF report to write, may be empty
#      RUNNER_TEMP   where the JSON report is kept
set -euo pipefail

SCAN_PATH="${SCAN_PATH:-.}"
FAIL_ON="${FAIL_ON:-high}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"

case "$FAIL_ON" in
  low) SEVERITIES=LOW,MEDIUM,HIGH,CRITICAL ;;
  medium) SEVERITIES=MEDIUM,HIGH,CRITICAL ;;
  high) SEVERITIES=HIGH,CRITICAL ;;
  critical) SEVERITIES=CRITICAL ;;
  *)
    echo "::error::config-scan: fail-on must be low, medium, high or critical (got '$FAIL_ON')"
    exit 1
    ;;
esac
if [ ! -d "$SCAN_PATH" ]; then
  echo "::error::config-scan: directory not found: $SCAN_PATH"
  exit 1
fi

REPORT="$RUNNER_TEMP/config-scan.json"
trivy config --quiet --severity "$SEVERITIES" --format json --output "$REPORT" "$SCAN_PATH"

if [ -n "${REPORT_PATH:-}" ]; then
  trivy convert --quiet --format sarif --output "$REPORT_PATH" "$REPORT"
fi

# One annotation per finding, then the verdict.
python3 - "$REPORT" "$SCAN_PATH" "$FAIL_ON" << 'PY'
import json
import os
import sys

report, root, fail_on = sys.argv[1:4]
count = 0
for result in json.load(open(report)).get("Results") or []:
    for finding in result.get("Misconfigurations") or []:
        count += 1
        path = os.path.normpath(os.path.join(root, result.get("Target", "")))
        line = (finding.get("CauseMetadata") or {}).get("StartLine") or 1
        text = " ".join(f"{finding.get('Title', '')} {finding.get('PrimaryURL', '')}".split())
        print(f"::error file={path},line={line},title={finding.get('ID')} ({finding.get('Severity')})::{text}")
if count:
    sys.exit(f"❌ {count} misconfiguration(s) at {fail_on} or above in {root}")
print(f"✅ No misconfiguration at {fail_on} or above in {root}")
PY
