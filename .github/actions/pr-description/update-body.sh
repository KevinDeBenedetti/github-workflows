#!/usr/bin/env bash
# Store a generated description in the managed block of a pull request body
# (see merge-body.py), and save the body only when it changed.
#
# Talks to the REST API with curl rather than gh: the actions-runner image that
# self-hosted runners often use ships curl and jq but no GitHub CLI. The token
# goes through a header file, never on a command line.
#
# Env: GITHUB_TOKEN      token allowed to edit the pull request (required)
#      REPO              owner/name (required)
#      PR_NUMBER         pull request number (required)
#      DESCRIPTION_FILE  Markdown written by write-description.sh (required)
#      TITLE_FILE        title checked by split-title.py (optional: when the
#                        file is absent or empty, the title is left as it is)
#      GITHUB_API_URL    REST API root, set by the runner
#                        (default: https://api.github.com)
set -euo pipefail

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
: "${REPO:?REPO is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${DESCRIPTION_FILE:?DESCRIPTION_FILE is required}"
case "$PR_NUMBER" in
  *[!0-9]*)
    echo "PR_NUMBER must be a number, got '${PR_NUMBER}'" >&2
    exit 2
    ;;
esac

# The token travels only over TLS, to the API root the runner names. curl
# verifies the certificate and follows no redirect, so no other host sees it.
api_url="${GITHUB_API_URL:-https://api.github.com}"
case "$api_url" in
  https://[!/]*) ;;
  *)
    echo "GITHUB_API_URL must be an https:// URL, got '${api_url}'" >&2
    exit 2
    ;;
esac

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/pr-body.XXXXXX")"
trap 'rm -rf "$work"' EXIT

url="${api_url%/}/repos/${REPO}/pulls/${PR_NUMBER}"
(umask 077 && printf 'Authorization: Bearer %s\n' "$GITHUB_TOKEN" > "$work/auth-header")

# api RESPONSE_FILE [curl args...]: the response body lands in RESPONSE_FILE,
# error responses included, so a failure can print what GitHub answered.
api() {
  local response="$1"
  shift
  curl -sS --fail-with-body --retry 3 --retry-delay 2 --max-time 60 \
    -H @"$work/auth-header" \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    -o "$response" "$@"
}

# The current body, not the event's: it may have been edited since the push.
if ! api "$work/pr.json" "$url"; then
  echo "Could not read pull request #${PR_NUMBER}. GitHub answered:" >&2
  cat "$work/pr.json" >&2 2> /dev/null || true
  exit 1
fi
# -j adds no trailing newline, so an unchanged body compares equal below.
jq -j '.body // ""' "$work/pr.json" > "$work/current.md"

python3 "$here/merge-body.py" "$work/current.md" "$DESCRIPTION_FILE" "$work/new.md"

# Only the fields that changed go in the PATCH; nothing changed, no call.
jq -j '.title // ""' "$work/pr.json" > "$work/current-title"
: > "$work/new-title"
if [ -n "${TITLE_FILE:-}" ] && [ -s "$TITLE_FILE" ]; then
  cp "$TITLE_FILE" "$work/new-title"
fi
body_changed=false
title_changed=false
cmp -s "$work/current.md" "$work/new.md" || body_changed=true
if [ -s "$work/new-title" ] && ! cmp -s "$work/current-title" "$work/new-title"; then
  title_changed=true
fi

if [ "$body_changed" = false ] && [ "$title_changed" = false ]; then
  echo "The description of #${PR_NUMBER} is already up to date."
  exit 0
fi
jq -n --rawfile body "$work/new.md" --rawfile title "$work/new-title" \
  --argjson set_body "$body_changed" --argjson set_title "$title_changed" \
  '(if $set_body then {body: $body} else {} end) + (if $set_title then {title: $title} else {} end)' \
  > "$work/payload.json"
if ! api "$work/patched.json" -X PATCH --data-binary @"$work/payload.json" "$url"; then
  echo "Could not update pull request #${PR_NUMBER} (does the caller grant pull-requests: write?). GitHub answered:" >&2
  cat "$work/patched.json" >&2 2> /dev/null || true
  exit 1
fi
if [ "$title_changed" = true ]; then
  echo "Updated the title of #${PR_NUMBER}: $(tr -d '\r\n' < "$work/new-title")"
fi
if [ "$body_changed" = true ]; then
  echo "Updated the description of #${PR_NUMBER}."
fi
