#!/usr/bin/env bash
# Check the report settings of the perf and SEO workflows before any work
# starts: how long the artifact stays, whether there is one, and where an
# S3-compatible copy of the report goes. A wrong setting fails with an
# ::error:: that names the input; no secret is ever printed.
#
# Env: ARTIFACT_RETENTION_DAYS  days the artifact stays, a whole number 1-90
#      UPLOAD_ARTIFACT          true | false
#      S3_BUCKET                bucket of the S3 copy; empty: no copy
#      S3_ENDPOINT              https:// URL of the S3 API, a host and an
#                               optional port (required with S3_BUCKET)
#      S3_PREFIX                optional key prefix: letters, digits, . _ - /
#      S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY
#                               credentials (required with S3_BUCKET)
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

bucket="${S3_BUCKET:-}" endpoint="${S3_ENDPOINT:-}" prefix="${S3_PREFIX:-}"
if [[ -z "$bucket" ]]; then
  if [[ -n "$endpoint$prefix${S3_ACCESS_KEY_ID:-}${S3_SECRET_ACCESS_KEY:-}" ]]; then
    echo "::warning::report-s3-bucket is empty: the report is not copied to S3, whatever the other report-s3-* settings say"
  fi
  s3="none"
else
  # S3 and Backblaze B2 bucket names: 3 to 63 characters.
  [[ "$bucket" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{1,61}[A-Za-z0-9]$ ]] ||
    fail "report-s3-bucket must be 3 to 63 letters, digits, dots or hyphens, starting and ending with a letter or digit (got '${bucket}')"
  # A host, never credentials in the URL: they go in the secrets.
  [[ "$endpoint" =~ ^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?/?$ ]] ||
    fail "report-s3-endpoint must be the https:// URL of the S3 API host, such as https://s3.eu-central-003.backblazeb2.com (got '${endpoint}')"
  if [[ ! "$prefix" =~ ^[A-Za-z0-9._/-]*$ || ${#prefix} -gt 512 || "/$prefix/" == */../* || "/$prefix/" == */./* ]]; then
    fail "report-s3-prefix may only hold letters, digits and . _ - /, with no . or .. segment (got '${prefix}')"
  fi
  [[ -n "${S3_ACCESS_KEY_ID:-}" ]] ||
    fail "report-s3-bucket is set but the report-s3-access-key-id secret is empty"
  [[ -n "${S3_SECRET_ACCESS_KEY:-}" ]] ||
    fail "report-s3-bucket is set but the report-s3-secret-access-key secret is empty"
  s3="s3://${bucket} at ${endpoint%/}"
fi

if [[ "$upload" == true ]]; then
  echo "Report settings: artifact kept ${days} day(s), S3 copy: ${s3}."
else
  echo "Report settings: no artifact, S3 copy: ${s3}."
fi
