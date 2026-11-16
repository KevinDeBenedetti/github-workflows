#!/usr/bin/env bash
# Check the http(s) links of the docs Markdown files with lychee.
#
# Docs directory: $DOCS_DIR (default "docs") — set by the action's
# `docs-directory` input.
#
# Files
#   arguments         : the Markdown files passed (a run by hand before a push)
#   CHANGED_ONLY=true : the $DOCS_DIR/**/*.md files changed since $BASE, the
#                       change base the action's change-base step found. A page
#                       that rotted elsewhere never fails an unrelated change —
#                       the central site's weekly crawl reports it. No change
#                       base (a manual run, a base that cannot be fetched) →
#                       every file. A $BASE missing from the clone fails.
#   otherwise         : every $DOCS_DIR/**/*.md
#
# Never checked: links in code blocks (lychee's default), relative links
# (check-docs-links' job), loopback addresses — localhost dev servers in setup
# guides — and medium.com, which answers any non-browser client with a 403.
# lychee also reads a .lycheeignore (one regex per line) from the repository
# root. $GITHUB_TOKEN, when set, lifts github.com's rate limit; a link to a
# private repository still fails, as it does for readers.
set -euo pipefail

DOCS_DIR="${DOCS_DIR:-docs}"
DOCS_DIR="${DOCS_DIR%/}"

files=()
if [[ $# -gt 0 ]]; then
  for file in "$@"; do
    if [[ "$file" == *.md ]]; then files+=("${file#./}"); fi
  done
else
  base=""
  if [[ "${CHANGED_ONLY:-false}" == true ]]; then
    base="${BASE:-}"
    if [[ -z "$base" ]]; then
      echo "::notice::No change base for this run (a manual run, or a base that cannot be fetched) — checking every file."
    elif ! git cat-file -e "${base}^{commit}" 2>/dev/null; then
      # Inside the < <(…) below, a failing git diff would slip past set -e
      # and check nothing.
      echo "::error::Change base $base is not in the clone." >&2
      exit 1
    fi
  fi
  if [[ -n "$base" ]]; then
    while IFS= read -r -d '' file; do
      if [[ "$file" == *.md ]]; then files+=("$file"); fi
    done < <(git diff -z --name-only --diff-filter=d "$base" HEAD -- "$DOCS_DIR")
  else
    mapfile -t files < <(find "$DOCS_DIR" -name "*.md" -type f 2>/dev/null | sort || true)
  fi
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No Markdown file to check in $DOCS_DIR/."
  exit 0
fi

# An empty token would be sent as is and fail every github.com request.
if [[ -z "${GITHUB_TOKEN:-}" ]]; then unset GITHUB_TOKEN; fi

report="$(mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/lychee-report.XXXXXX")"
trap 'rm -f "$report"' EXIT

args=(
  --no-progress
  --scheme https --scheme http
  --exclude-loopback
  --exclude '^https://([^/]+\.)?medium\.com/'
  --max-retries 3 --retry-wait-time 5 --timeout 30
  --format markdown --output "$report"
)

echo "Checking the external links of ${#files[@]} file(s):"
printf '  %s\n' "${files[@]}"
status=0
lychee "${args[@]}" -- "${files[@]}" || status=$?

cat "$report"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat "$report" >> "$GITHUB_STEP_SUMMARY"
fi
if (( status != 0 )); then
  echo "::error::Broken external links in $DOCS_DIR/ — see the lychee report above (also in the job summary)."
fi
exit "$status"
