#!/usr/bin/env bash
# Copy a report directory to S3-compatible storage (Backblaze B2, AWS S3,
# MinIO…) with rclone, under
#
#   <prefix>/<owner>/<repo>/<workflow>/<run id>-<run attempt>/<name>/
#
# and write that path to the job summary. <name> is the report's artifact
# name, so two jobs of one run (the devices of a matrix, two calls of one
# workflow) never write over each other.
#
# rclone is downloaded at the pinned version and checked against the pinned
# SHA-256 of its .deb before it runs. dpkg-deb, in every Debian and Ubuntu
# image, unpacks a .deb without root, where unzip may be missing (the
# sitespeed.io image has none). The credentials reach rclone through its
# environment only: never on a command line, never in a file, never printed.
# A write-only key is enough: rclone neither lists, reads nor creates anything.
#
# Env: REPORT_DIR       directory to copy; missing: a warning, nothing copied
#      REPORT_NAME      folder of the report under the run (the artifact name)
#      REPORT_WORKFLOW  workflow segment of the path (perf-sitespeed, …)
#      S3_ENDPOINT      https:// URL of the S3 API host
#      S3_BUCKET        bucket
#      S3_PREFIX        optional key prefix
#      S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY
#      RCLONE_VERSION, RCLONE_SHA256_amd64, RCLONE_SHA256_arm64
#                       the pins, set by action.yml
#      GITHUB_REPOSITORY, GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT, RUNNER_TEMP,
#      GITHUB_STEP_SUMMARY, GITHUB_OUTPUT  set by the runner
# Output (GITHUB_OUTPUT): path, the s3:// path of the copy.
# Needs bash, curl or wget (the sitespeed.io image has no curl), sha256sum and
# dpkg-deb.
set -euo pipefail

fail() {
  echo "::error::$*" >&2
  exit 1
}

report_dir="${REPORT_DIR:-}"
name="${REPORT_NAME:-}"
workflow="${REPORT_WORKFLOW:-}"
endpoint="${S3_ENDPOINT:-}"
bucket="${S3_BUCKET:-}"
prefix="${S3_PREFIX:-}"
version="${RCLONE_VERSION:-}"

# The same rules as check-report-inputs, checked again here, whoever calls.
[[ "$name" =~ ^[A-Za-z0-9._-]+$ && "$name" != . && "$name" != .. ]] ||
  fail "REPORT_NAME must be a folder name: letters, digits and . _ - (got '${name}')"
[[ "$workflow" =~ ^[a-z0-9][a-z0-9-]*$ ]] ||
  fail "REPORT_WORKFLOW must be lowercase letters, digits and hyphens (got '${workflow}')"
[[ "$bucket" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{1,61}[A-Za-z0-9]$ ]] ||
  fail "the bucket must be 3 to 63 letters, digits, dots or hyphens, starting and ending with a letter or digit (got '${bucket}')"
[[ "$endpoint" =~ ^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?/?$ ]] ||
  fail "the endpoint must be the https:// URL of the S3 API host (got '${endpoint}')"
if [[ ! "$prefix" =~ ^[A-Za-z0-9._/-]*$ || ${#prefix} -gt 512 || "/$prefix/" == */../* || "/$prefix/" == */./* ]]; then
  fail "the prefix may only hold letters, digits and . _ - /, with no . or .. segment (got '${prefix}')"
fi
[[ -n "${S3_ACCESS_KEY_ID:-}" && -n "${S3_SECRET_ACCESS_KEY:-}" ]] ||
  fail "the access key ID and the secret access key are both required"
[[ "${GITHUB_REPOSITORY:-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
  fail "GITHUB_REPOSITORY must be owner/name (got '${GITHUB_REPOSITORY:-}')"
[[ "${GITHUB_RUN_ID:-}" =~ ^[0-9]+$ && "${GITHUB_RUN_ATTEMPT:-}" =~ ^[0-9]+$ ]] ||
  fail "GITHUB_RUN_ID and GITHUB_RUN_ATTEMPT must be numbers"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  fail "RCLONE_VERSION must be a version such as 1.75.2 (got '${version}')"

if [[ ! -d "$report_dir" ]]; then
  echo "::warning::${report_dir:-REPORT_DIR} is not a directory: no report to copy to S3"
  exit 0
fi

# A prefix is a path of segments: leading, trailing and doubled slashes go.
prefix="$(printf '%s' "$prefix" | tr -s /)"
prefix="${prefix#/}"
prefix="${prefix%/}"
dest="${prefix:+$prefix/}${GITHUB_REPOSITORY}/${workflow}/${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}/${name}"

case "$(uname -m)" in
  x86_64 | amd64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) fail "rclone: unsupported architecture $(uname -m)" ;;
esac
want_var="RCLONE_SHA256_${arch}"
want="${!want_var:-}"
[[ "$want" =~ ^[0-9a-f]{64}$ ]] || fail "${want_var} must be a SHA-256 (got '${want}')"

work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/upload-report-s3.XXXXXX")"
trap 'rm -rf "$work"' EXIT

asset="rclone-v${version}-linux-${arch}.deb"
url="https://github.com/rclone/rclone/releases/download/v${version}/${asset}"
if command -v curl > /dev/null 2>&1; then
  curl -sSfL --retry 5 --retry-delay 5 --retry-all-errors -o "$work/rclone.deb" "$url" ||
    fail "rclone: could not download ${url}"
elif command -v wget > /dev/null 2>&1; then
  wget -q --tries=5 --waitretry=5 -O "$work/rclone.deb" "$url" ||
    fail "rclone: could not download ${url}"
else
  fail "rclone: neither curl nor wget is there to download it"
fi
echo "$want  $work/rclone.deb" | sha256sum --check --strict --quiet - ||
  fail "rclone ${version} (${arch}) does not match its pinned SHA-256 — after a version bump, run scripts/update-tool-checksums.py"
dpkg-deb -x "$work/rclone.deb" "$work/rclone" || fail "rclone: dpkg-deb could not unpack ${asset}"
rclone="$work/rclone/usr/bin/rclone"
[[ -x "$rclone" ]] || fail "rclone: no usr/bin/rclone in ${asset}"

# Backblaze B2 and AWS name the region in the endpoint, and sign with it.
host="${endpoint#https://}"
host="${host%%/*}"
host="${host%%:*}"
region=""
if [[ "$host" =~ ^s3\.([a-z0-9-]+)\.(backblazeb2\.com|amazonaws\.com)$ ]]; then
  region="${BASH_REMATCH[1]}"
fi

# The remote lives in these variables alone: the config file is empty, so a
# stray ~/.config/rclone/rclone.conf is never read, nor AWS_* variables.
: > "$work/rclone.conf"
export RCLONE_CONFIG="$work/rclone.conf"
export RCLONE_CONFIG_REPORT_TYPE=s3
export RCLONE_CONFIG_REPORT_PROVIDER=Other
export RCLONE_CONFIG_REPORT_ENDPOINT="${endpoint%/}"
export RCLONE_CONFIG_REPORT_REGION="$region"
export RCLONE_CONFIG_REPORT_ENV_AUTH=false
export RCLONE_CONFIG_REPORT_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID"
export RCLONE_CONFIG_REPORT_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY"
# A write-only key: no bucket check or creation, no HEAD after an upload.
export RCLONE_CONFIG_REPORT_NO_CHECK_BUCKET=true
export RCLONE_CONFIG_REPORT_NO_HEAD=true
unset S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY

files="$(find "$report_dir" -type f | wc -l | tr -d ' ')"
kib="$(du -sk "$report_dir" | cut -f1)"
tenths=$(((kib * 10 + 512) / 1024))
size="$((tenths / 10)).$((tenths % 10))"
path="s3://${bucket}/${dest}/"
echo "Copying ${files} file(s), ${size} MB, of ${report_dir} to ${path} (${endpoint%/}), with rclone ${version}."
# --no-check-dest: nothing listed, every file sent, as a write-only key needs.
"$rclone" copy "$report_dir" "report:${bucket}/${dest}" --no-check-dest --stats 0 --log-level NOTICE ||
  fail "rclone could not copy ${report_dir} to ${path} (its log is above)"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'path=%s\n' "$path" >> "$GITHUB_OUTPUT"
fi
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  # shellcheck disable=SC2016 # Markdown code marks, not a command substitution
  printf '### Report copy\n\n`%s` on %s: %s file(s), %s MB.\n' \
    "$path" "${endpoint%/}" "$files" "$size" >> "$GITHUB_STEP_SUMMARY"
fi
echo "Copied to ${path}"
