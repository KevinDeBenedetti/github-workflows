#!/usr/bin/env bash
# Check the report settings of the perf and SEO workflows before any work
# starts: how long the artifact stays, and whether there is one. A wrong
# setting fails with an ::error:: that names the input.
#
# Env: ARTIFACT_RETENTION_DAYS  days the artifact stays, a whole number 1-90
#      UPLOAD_ARTIFACT          true | false
set -euo pipefail

fail() {
  echo "::error::$*" >&2
  exit 1
}

days="${ARTIFACT_RETENTION_DAYS:-}"
if [[ ! "$days" =~ ^[0-9]{1,2}$ ]] || ((10#$days < 1 || 10#$days > 90)); then
  fail "artifact-retention-days must be a whole number from 1 to 90 (got '${days}')"
fi
upload="${UPLOAD_ARTIFACT:-}"
case "$upload" in
  true | false) ;;
  *) fail "upload-artifact must be true or false (got '${upload}')" ;;
esac

if [[ "$upload" == true ]]; then
  echo "Report settings: artifact kept ${days} day(s)."
else
  echo "Report settings: no artifact."
fi
