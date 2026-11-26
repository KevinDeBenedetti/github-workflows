#!/usr/bin/env bash
# Audit the dependencies of every lockfile under SCAN_PATH with OSV-Scanner,
# whatever the ecosystem (npm, pnpm, bun, PyPI, Go, Cargo, …), against the
# OSV advisory database.
#
# osv-scanner's exit code decides: 0 passes, 1 (a known vulnerability) fails,
# 128 (no lockfile found) passes with a notice, anything else is a scan that
# could not complete and fails with that code. Ignore an advisory in the
# caller's osv-scanner.toml.
#
# Env: SCAN_PATH   directory to scan, recursively
set -euo pipefail

SCAN_PATH="${SCAN_PATH:-.}"
if [ ! -d "$SCAN_PATH" ]; then
  echo "::error::osv-scan: directory not found: $SCAN_PATH"
  exit 1
fi

code=0
osv-scanner scan source --recursive "$SCAN_PATH" || code=$?

case "$code" in
  0)
    echo "✅ No known vulnerability in the dependencies under $SCAN_PATH"
    ;;
  1)
    echo "::error::osv-scan: known vulnerabilities in the dependencies under $SCAN_PATH (listed above)"
    exit 1
    ;;
  128)
    echo "::notice::osv-scan: no lockfile or manifest found under $SCAN_PATH, nothing to audit"
    ;;
  *)
    echo "::error::osv-scan: osv-scanner could not complete the scan (exit $code)"
    exit "$code"
    ;;
esac
