#!/usr/bin/env bash
# Summarize a Lighthouse CI run and post it as commit statuses: one row per
# page in the job summary, one status per page (`lighthouse/en`, …), red when
# one of the page's `error` assertions failed, its category scores in the
# description.
#
# `lhci upload` posts statuses only for reports it sends to a Lighthouse CI
# server or to its public storage, a third-party service. This script reads
# what `lhci assert` and `lhci upload --target=filesystem` leave on disk and
# talks to the REST API with curl rather than gh: the actions-runner image that
# self-hosted runners often use ships curl and jq but no GitHub CLI. The token
# goes through a header file, never on a command line.
#
#   $REPORT_DIR/manifest.json  every run; the median one of each URL is marked
#                              isRepresentativeRun, with its JSON report
#   $ASSERTIONS_FILE           results of `lhci assert`, keyed by each report's
#                              final URL (absent when nothing was asserted)
#
# Env: REPORT_DIR       lhci filesystem output (default .lighthouse)
#      ASSERTIONS_FILE  default .lighthouseci/assertion-results.json
#      POST_STATUSES    true | false (default true)
#      SHA              commit the statuses go on (default $GITHUB_SHA)
#      VERSION_URL      optional URL of a JSON document whose `version` is the
#                       release tag the audited site runs: the statuses go on
#                       that tag's commit instead, or are skipped, with a
#                       warning, when it names no tag of the repository
#      TARGET_URL       link of every status (default: this workflow run)
#      CONTEXT_PREFIX   status context before the page path (default lighthouse)
#      GITHUB_TOKEN     statuses: write, plus contents: read for VERSION_URL
#                       (required to post)
#      GITHUB_REPOSITORY, GITHUB_API_URL, GITHUB_SERVER_URL, GITHUB_RUN_ID,
#      GITHUB_STEP_SUMMARY  set by the runner
set -euo pipefail

REPORT_DIR="${REPORT_DIR:-.lighthouse}"
ASSERTIONS_FILE="${ASSERTIONS_FILE:-.lighthouseci/assertion-results.json}"
POST_STATUSES="${POST_STATUSES:-true}"
CONTEXT_PREFIX="${CONTEXT_PREFIX:-lighthouse}"
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
manifest="$REPORT_DIR/manifest.json"

if [[ ! -f "$manifest" ]]; then
  echo "No ${manifest}: Lighthouse produced no report, nothing to summarize."
  printf '### Lighthouse CI\n\n_No report produced._\n' >> "$summary"
  exit 0
fi
if ! jq -e 'type == "array"' "$manifest" > /dev/null; then
  echo "${manifest} is not a Lighthouse CI manifest (a JSON array)." >&2
  exit 1
fi

work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/lighthouse-results.XXXXXX")"
trap 'rm -rf "$work"' EXIT

if [[ -f "$ASSERTIONS_FILE" ]]; then
  cp "$ASSERTIONS_FILE" "$work/assertions.json"
else
  echo '[]' > "$work/assertions.json"
fi

# One JSON line per page: its path, its failed assertions and its scores.
: > "$work/pages.jsonl"
while IFS=$'\t' read -r url json_path; do
  report="$json_path"
  # jsonPath is absolute on the machine that ran lhci: a report downloaded
  # elsewhere sits next to its manifest.
  [[ -f "$report" ]] || report="$REPORT_DIR/$(basename "$json_path")"
  jq -c --arg url "$url" --slurpfile assertions "$work/assertions.json" '
    # The assert step keys its results by the URL the page ended on, which a
    # redirect makes differ from the one requested.
    (.finalUrl // $url) as $final
    | [$assertions[0][] | select(.url == $final and .level == "error" and (.passed | not))] as $failed
    | {
        path: ($url | sub("^[a-z]+://[^/]+"; "") | if . == "" then "/" else . end),
        failed: ($failed | length),
        failedCategories: [$failed[] | select(.auditId == "categories") | .auditProperty],
        scores: [.categories | to_entries[] | {
          id: .key,
          title: .value.title,
          score: (if .value.score == null then null else .value.score * 100 | round end)
        }]
      }' "$report" >> "$work/pages.jsonl"
done < <(jq -r '.[] | select(.isRepresentativeRun) | [.url, .jsonPath] | @tsv' "$manifest")

{
  echo '### Lighthouse CI'
  echo
  jq -rs '
    if length == 0 then "_No representative run in the manifest._" else
      (.[0].scores | map(.title)) as $titles
      | "| Page | \($titles | join(" | ")) | Result |",
        "| --- | \($titles | map("---") | join(" | ")) | --- |",
        (.[] | .failedCategories as $failedCategories
          | "| \(.path) | \(.scores | map(
                (.score // "n/a" | tostring) as $score
                | .id as $id
                | if any($failedCategories[]; . == $id) then "❌ \($score)" else $score end
              ) | join(" | ")) | \(if .failed > 0 then "❌ \(.failed) failed" else "✅" end) |")
    end' "$work/pages.jsonl"
} >> "$summary"

if [[ "$POST_STATUSES" != true ]]; then
  echo "Summary written; no status posted (post-statuses: ${POST_STATUSES})."
  exit 0
fi

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required to post statuses}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
api_root="${GITHUB_API_URL:-https://api.github.com}"
(umask 077 && printf 'Authorization: Bearer %s\n' "$GITHUB_TOKEN" > "$work/auth-header")

# api RESPONSE_FILE [curl args...]: the response body lands in RESPONSE_FILE,
# error responses included, so a failure can print what GitHub answered.
api() {
  local response="$1"
  shift
  curl -sS --fail-with-body --retry 3 --retry-delay 2 \
    -H @"$work/auth-header" \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    -o "$response" "$@"
}

sha="${SHA:-${GITHUB_SHA:-}}"
if [[ -n "${VERSION_URL:-}" ]]; then
  # The site's answer is not trusted: only a tag-shaped version is looked up,
  # and nothing else of it is printed.
  version="$(curl -sS --max-time 20 "$VERSION_URL" | jq -r '.version | strings' 2> /dev/null || true)"
  sha=""
  if [[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]{0,99}$ && "$version" != unknown ]]; then
    for ref in "$version" "v${version}"; do
      [[ "$ref" == vv* ]] && continue
      if api "$work/commit.json" "$api_root/repos/${GITHUB_REPOSITORY}/commits/${ref}"; then
        sha="$(jq -r '.sha // empty' "$work/commit.json")"
        [[ -n "$sha" ]] && break
      fi
    done
  fi
  if [[ -z "$sha" ]]; then
    echo "::warning::${VERSION_URL} names no release tag of ${GITHUB_REPOSITORY}: no status posted, the scores are in the job summary."
    exit 0
  fi
  echo "${VERSION_URL} runs ${version}, commit ${sha}."
fi
: "${sha:?SHA or GITHUB_SHA is required}"

target_url="${TARGET_URL:-}"
if [[ -z "$target_url" && -n "${GITHUB_RUN_ID:-}" ]]; then
  target_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
fi

refused=0
while IFS= read -r page; do
  jq -n --argjson page "$page" --arg prefix "$CONTEXT_PREFIX" --arg target "$target_url" '
    ($page.scores | map("\(.title): \(.score // "n/a")") | join(", ")) as $scores
    | {
        state: (if $page.failed > 0 then "failure" else "success" end),
        context: "\($prefix)\($page.path)",
        # GitHub refuses a description longer than 140 characters.
        description: (if $page.failed > 0 then "Failed \($page.failed) assertion(s) — \($scores)" else $scores end)[0:140]
      }
    + (if $target == "" then {} else {target_url: $target} end)' > "$work/status.json"
  context="$(jq -r .context "$work/status.json")"
  if api "$work/response.json" -X POST --data-binary @"$work/status.json" \
    "$api_root/repos/${GITHUB_REPOSITORY}/statuses/${sha}"; then
    echo "Posted ${context}: $(jq -r '"\(.state) — \(.description)"' "$work/status.json")"
  else
    refused=$((refused + 1))
    echo "Could not post ${context} (does the caller grant statuses: write?). GitHub answered:" >&2
    cat "$work/response.json" >&2 2> /dev/null || true
  fi
done < "$work/pages.jsonl"

if ((refused > 0)); then
  echo "${refused} status(es) refused." >&2
  exit 1
fi
