#!/usr/bin/env bash
# Delete the old deployment records of a repository, so that its Deployments
# page and its environments list what is deployed, not every deploy ever made.
#
# A deployment record is what a deploy job leaves behind (environment, commit,
# statuses). It holds no file and costs no storage: this is tidiness, and it
# never touches what is deployed, the environments or their secrets.
#
# Rules:
#   never deleted  deployments younger than OLDER_THAN_DAYS, and the KEEP most
#                  recent ones of each environment, whatever their age: the
#                  record of what runs there now is always among them.
#   deleted        every other deployment, oldest first, MAX_DELETIONS at
#                  most per run. GitHub refuses to delete an active
#                  deployment, so each one is first given the `inactive`
#                  status, then deleted.
#
# Environment:
#   KEEP               deployments kept per environment, 1 to 100 (default 5)
#   OLDER_THAN_DAYS    age in days before a deployment can go, 0 or more (default 30)
#   MAX_DELETIONS      deletions at most in one run, 1 to 400 (default 200):
#                      each takes two requests of the token's 1,000 an hour
#   DRY_RUN            true: print what would be deleted, delete nothing
#   DELETE_INTERVAL    seconds between two deletions (default 1)
#   GITHUB_TOKEN       deployments write (required)
#   GITHUB_REPOSITORY  owner/name (required)
#   GITHUB_API_URL     REST API root, set by the runner
#   GITHUB_OUTPUT, GITHUB_STEP_SUMMARY  set by the runner
set -euo pipefail

KEEP="${KEEP:-5}"
OLDER_THAN_DAYS="${OLDER_THAN_DAYS:-30}"
MAX_DELETIONS="${MAX_DELETIONS:-200}"
DRY_RUN="${DRY_RUN:-false}"
DELETE_INTERVAL="${DELETE_INTERVAL:-1}"
# Pages of 100 deployments read at most: 5,000 records.
PAGES=50

fail() {
  echo "::error::$*" >&2
  exit 1
}

# Whole numbers within bounds, stored without leading zeros.
for setting in "KEEP 1 100" "OLDER_THAN_DAYS 0 36500" "MAX_DELETIONS 1 400" "DELETE_INTERVAL 0 60"; do
  read -r name min max <<< "$setting"
  value="${!name}"
  if [[ ! "$value" =~ ^[0-9]{1,9}$ ]] || ((10#$value < min || 10#$value > max)); then
    fail "$name must be a whole number from $min to $max, not '$value'"
  fi
  printf -v "$name" '%d' "$((10#$value))"
done
case "$DRY_RUN" in
  true | false) ;;
  *) fail "DRY_RUN must be true or false, not '$DRY_RUN'" ;;
esac

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
[[ "$GITHUB_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
  fail "GITHUB_REPOSITORY must be owner/name, not '$GITHUB_REPOSITORY'"
# The token travels only over TLS, to the API root the runner names.
api_url="${GITHUB_API_URL:-https://api.github.com}"
case "$api_url" in
  https://[!/]*) ;;
  *) fail "GITHUB_API_URL must be an https:// URL, not '$api_url'" ;;
esac
api_root="${api_url%/}/repos/${GITHUB_REPOSITORY}"

work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/cleanup-deployments.XXXXXX")"
trap 'rm -rf "$work"' EXIT
(umask 077 && printf 'Authorization: Bearer %s\n' "$GITHUB_TOKEN" > "$work/auth-header")

# api RESPONSE [curl args...]: prints the HTTP status; the body, error answers
# included, lands in RESPONSE.
api() {
  local response="$1"
  shift
  curl -sS --retry 3 --retry-delay 2 --max-time 60 \
    -H @"$work/auth-header" \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    -o "$response" -w '%{http_code}' "$@"
}
message() { jq -r '.message? // empty' "$1" 2> /dev/null || true; }

# Every deployment, newest first (GitHub's order), one JSON value per line.
: > "$work/deployments.jsonl"
page=1
while ((page <= PAGES)); do
  status="$(api "$work/page.json" "${api_root}/deployments?per_page=100&page=${page}")"
  [[ "$status" == 200 ]] ||
    fail "GitHub answered $status listing the deployments: $(message "$work/page.json") (does the job grant deployments: write?)"
  jq -c '.[] | {id, environment, created_at, sha}' "$work/page.json" >> "$work/deployments.jsonl"
  (($(jq length "$work/page.json") == 100)) || break
  page=$((page + 1))
done

# The deployments to delete, oldest first: older than the cutoff and not among
# the KEEP most recent of their environment.
jq -cs --argjson keep "$KEEP" --argjson days "$OLDER_THAN_DAYS" '
  ((now | floor) - $days * 86400 | strftime("%Y-%m-%dT%H:%M:%SZ")) as $cutoff
  | group_by(.environment)
  | map(sort_by(.created_at, .id) | reverse | .[$keep:] | map(select(.created_at < $cutoff)))
  | add // []
  | sort_by(.created_at, .id)
  | .[]' "$work/deployments.jsonl" > "$work/candidates.jsonl"

total="$(wc -l < "$work/deployments.jsonl" | tr -d ' ')"
candidates="$(wc -l < "$work/candidates.jsonl" | tr -d ' ')"
deleted=0
failed=0

while IFS= read -r deployment; do
  ((deleted + failed < MAX_DELETIONS)) || break
  id="$(jq -r .id <<< "$deployment")"
  label="$(jq -r '"deployment \(.id) of \(.created_at[0:10]) to \(.environment) (\(.sha[0:7]))"' <<< "$deployment")"
  if [[ "$DRY_RUN" == true ]]; then
    echo "Would delete $label"
    deleted=$((deleted + 1))
    continue
  fi
  ((deleted + failed == 0)) || sleep "$DELETE_INTERVAL"
  # An active deployment cannot be deleted: retire it first.
  status="$(api "$work/answer.json" -X POST -d '{"state":"inactive"}' "${api_root}/deployments/${id}/statuses")"
  if [[ "$status" != 201 ]]; then
    echo "::warning::Could not retire $label: GitHub answered $status $(message "$work/answer.json")"
    failed=$((failed + 1))
    continue
  fi
  status="$(api "$work/answer.json" -X DELETE "${api_root}/deployments/${id}")"
  case "$status" in
    204 | 404)
      echo "Deleted $label"
      deleted=$((deleted + 1))
      ;;
    *)
      echo "::warning::Could not delete $label: GitHub answered $status $(message "$work/answer.json")"
      failed=$((failed + 1))
      ;;
  esac
done < "$work/candidates.jsonl"

remaining=$((candidates - deleted - failed))
verb="Deleted"
[[ "$DRY_RUN" == false ]] || verb="Would delete"
summary="$verb $deleted of $total deployment(s); $failed failed, $remaining left for a later run."
echo "$summary"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "deleted=$deleted"
    echo "remaining=$remaining"
  } >> "$GITHUB_OUTPUT"
fi
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### Deployment cleanup"
    echo
    echo "$summary Kept: the $KEEP most recent of each environment and those younger than $OLDER_THAN_DAYS day(s)."
  } >> "$GITHUB_STEP_SUMMARY"
fi

# Every attempt failed: the token or the permissions are wrong, say so.
if ((failed > 0 && deleted == 0)); then
  fail "no deployment could be deleted ($failed failed): does the job grant deployments: write?"
fi
