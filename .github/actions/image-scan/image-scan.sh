#!/usr/bin/env bash
# Scan a container image of the runner's Docker daemon for known
# vulnerabilities with `trivy image` (OS packages and language libraries).
#
# Every vulnerability at FAIL_ON or above is listed in the job summary and
# fails the step, whether a fix exists or not. Silence one in the caller's
# .trivyignore.
#
# Env: IMAGE                 image reference, loaded in the Docker daemon
#      FAIL_ON               lowest severity that fails: low, medium, high or critical
#      RUNNER_TEMP           where the JSON report is kept
#      GITHUB_STEP_SUMMARY   the job summary
set -euo pipefail

IMAGE="${IMAGE:-}"
FAIL_ON="${FAIL_ON:-critical}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"

case "$FAIL_ON" in
  low) SEVERITIES=LOW,MEDIUM,HIGH,CRITICAL ;;
  medium) SEVERITIES=MEDIUM,HIGH,CRITICAL ;;
  high) SEVERITIES=HIGH,CRITICAL ;;
  critical) SEVERITIES=CRITICAL ;;
  *)
    echo "::error::image-scan: fail-on must be low, medium, high or critical (got '$FAIL_ON')"
    exit 1
    ;;
esac
if [ -z "$IMAGE" ]; then
  echo "::error::image-scan: no image to scan"
  exit 1
fi

REPORT="$RUNNER_TEMP/image-scan.json"
trivy image --quiet --scanners vuln --severity "$SEVERITIES" --format json --output "$REPORT" "$IMAGE"

python3 - "$REPORT" "$IMAGE" "$FAIL_ON" "${GITHUB_STEP_SUMMARY:-/dev/null}" << 'PY'
import json
import sys

report, image, fail_on, summary = sys.argv[1:5]


def cell(value):
    return " ".join(str(value or "").split()).replace("|", "\\|")


rows = []
for result in json.load(open(report)).get("Results") or []:
    for v in result.get("Vulnerabilities") or []:
        rows.append(
            f"| `{cell(v.get('PkgName'))}` | [{cell(v.get('VulnerabilityID'))}]({v.get('PrimaryURL', '')}) "
            f"| {cell(v.get('Severity'))} | {cell(v.get('InstalledVersion'))} | {cell(v.get('FixedVersion'))} "
            f"| {cell(v.get('Title'))} |"
        )
with open(summary, "a") as out:
    out.write(f"### 🔎 Image scan\n\n`{image}`\n\n")
    if rows:
        out.write("| Package | Vulnerability | Severity | Installed | Fixed in | Title |\n")
        out.write("|---------|---------------|----------|-----------|----------|-------|\n")
        out.write("\n".join(rows) + "\n")
    else:
        out.write(f"No vulnerability at `{fail_on}` or above.\n")
if rows:
    sys.exit(f"❌ {len(rows)} vulnerabilities at {fail_on} or above in {image} (see the job summary)")
print(f"✅ No vulnerability at {fail_on} or above in {image}")
PY
