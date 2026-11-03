#!/usr/bin/env bash
# Delete the old workflow runs of a repository, with their logs and artifacts,
# and keep the recent ones.
#
# A run is deleted only when all of these hold:
#   - it is completed: a queued, running or waiting run is never touched;
#   - it was created before the cutoff day, OLDER_THAN_DAYS days ago (UTC);
#   - it is not among the KEEP_RUNS most recent runs of its workflow. A
#     workflow whose file was deleted keeps none: once its last run is old
#     enough, it leaves the Actions sidebar;
#   - its commit is neither the head of an open pull request nor GITHUB_SHA
#     (on a schedule, the last commit of the default branch): their checks
#     stay visible.
# The oldest go first, at most MAX_DELETIONS per run, DELETE_INTERVAL seconds
# apart: a GITHUB_TOKEN may send 1,000 REST requests an hour per repository,
# and GitHub asks for a pause between deletions. GitHub lists at most 1,000
# runs per query, so a larger backlog takes several runs.
#
# Talks to the REST API with curl, the token in a header file, never on a
# command line: self-hosted runner images often ship no GitHub CLI.
#
# Env: KEEP_RUNS          most recent runs kept per workflow, 0-100 (default 10)
#      OLDER_THAN_DAYS    age in days before a run can go, 1 or more (default 30)
#      MAX_DELETIONS      runs deleted at most in one run, 1-1000 (default 500)
#      DRY_RUN            true: print what would be deleted, delete nothing
#                         (default false)
#      DELETE_INTERVAL    seconds between two deletions (default 1)
#      GITHUB_TOKEN       actions write, pull-requests read (required)
#      GITHUB_REPOSITORY  owner/name (required)
#      GITHUB_SHA         a commit whose runs are kept (optional)
#      GITHUB_API_URL     REST API root, set by the runner
#                         (default: https://api.github.com)
# Outputs (GITHUB_OUTPUT, and stdout): deleted, remaining. The job summary
# counts the deletions per workflow.
set -euo pipefail

KEEP_RUNS="${KEEP_RUNS:-10}"
OLDER_THAN_DAYS="${OLDER_THAN_DAYS:-30}"
MAX_DELETIONS="${MAX_DELETIONS:-500}"
DRY_RUN="${DRY_RUN:-false}"
DELETE_INTERVAL="${DELETE_INTERVAL:-1}"

fail() {
  echo "::error::$*" >&2
  exit 1
}

# Whole numbers within bounds, stored without leading zeros.
for setting in "KEEP_RUNS 0 100" "OLDER_THAN_DAYS 1 36500" "MAX_DELETIONS 1 1000" "DELETE_INTERVAL 0 60"; do
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
GITHUB_SHA="${GITHUB_SHA:-}"
[[ -z "$GITHUB_SHA" || "$GITHUB_SHA" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] ||
  fail "GITHUB_SHA must be a full commit SHA, not '$GITHUB_SHA'"
# The token travels only over TLS, to the API root the runner names.
api_url="${GITHUB_API_URL:-https://api.github.com}"
case "$api_url" in
  https://[!/]*) ;;
  *) fail "GITHUB_API_URL must be an https:// URL, not '$api_url'" ;;
esac
api_root="${api_url%/}/repos/${GITHUB_REPOSITORY}"

work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/cleanup-runs.XXXXXX")"
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

# list PATH ITEMS FIELDS OUT: FIELDS of each element of the ITEMS array, page
# after page of PATH, one JSON value per line in OUT. Ten pages at most: GitHub
# ends a filtered query at 1,000 results.
list() {
  local path="$1" items="$2" fields="$3" out="$4" page=1 sep='?' status
  if [[ "$path" == *\?* ]]; then
    sep='&'
  fi
  : > "$out"
  while ((page <= 10)); do
    status="$(api "$work/page.json" "${api_root}${path}${sep}per_page=100&page=${page}")"
    case "$status" in
      200) ;;
      403 | 404)
        fail "GitHub answered $status listing ${path%%\?*}: $(message "$work/page.json") (does the job grant actions: write and pull-requests: read?)"
        ;;
      *) fail "GitHub answered $status listing ${path%%\?*}: $(message "$work/page.json")" ;;
    esac
    jq -c "${items}[] | ${fields}" "$work/page.json" >> "$out"
    (($(jq "${items} | length" "$work/page.json") == 100)) || break
    page=$((page + 1))
  done
}

cutoff="$(jq -rn --argjson days "$OLDER_THAN_DAYS" '(now | floor) - $days * 86400 | strftime("%Y-%m-%d")')"

# The old runs first: without any, nothing else needs asking.
list "/actions/runs?status=completed&created=%3C${cutoff}" .workflow_runs \
  '{id, workflow_id, path, status, created_at, head_sha}' "$work/runs.jsonl"
: > "$work/workflows.jsonl"
: > "$work/protected.jsonl"
: > "$work/kept.jsonl"
if [[ -s "$work/runs.jsonl" ]]; then
  list /actions/workflows .workflows '{id, state}' "$work/workflows.jsonl"
  list "/pulls?state=open" . '.head.sha' "$work/protected.jsonl"
  if [[ -n "$GITHUB_SHA" ]]; then
    jq -n --arg sha "$GITHUB_SHA" '$sha' >> "$work/protected.jsonl"
  fi

  # The KEEP_RUNS most recent runs of each workflow that has old runs and
  # still has its file: one request per workflow.
  jq -rn --slurpfile workflows "$work/workflows.jsonl" --slurpfile runs "$work/runs.jsonl" '
    ($workflows | map(select(.state != "deleted") | {key: (.id | tostring), value: true}) | from_entries) as $live
    | [$runs[].workflow_id] | unique[] | select($live[tostring] == true)' > "$work/live-ids"
  if ((KEEP_RUNS > 0)); then
    while read -r id; do
      [[ "$id" =~ ^[0-9]+$ ]] || fail "unexpected workflow id '$id'"
      status="$(api "$work/recent.json" "${api_root}/actions/workflows/${id}/runs?per_page=${KEEP_RUNS}")"
      [[ "$status" == 200 ]] ||
        fail "GitHub answered $status listing the runs of workflow ${id}: $(message "$work/recent.json")"
      jq -c '.workflow_runs[].id' "$work/recent.json" >> "$work/kept.jsonl"
    done < "$work/live-ids"
  fi
fi

# Every rule checked again here, whatever the query returned. A path is only
# printed with unusual characters replaced: it comes from a workflow file.
jq -cn \
  --slurpfile runs "$work/runs.jsonl" \
  --slurpfile kept "$work/kept.jsonl" \
  --slurpfile protected "$work/protected.jsonl" \
  --slurpfile workflows "$work/workflows.jsonl" \
  --arg cutoff "$cutoff" '
  def lookup: map({key: tostring, value: true}) | from_entries;
  ($kept | lookup) as $kept
  | ($protected | lookup) as $protected
  | ($workflows | map(select(.state != "deleted") | .id) | lookup) as $live
  | $runs
  | map(select(
      (.id | type) == "number"
      and .status == "completed"
      and (.created_at | type) == "string" and .created_at < $cutoff
      and ($kept[.id | tostring] | not)
      and ($protected[.head_sha // "" | tostring] | not)))
  | unique_by(.id)
  | sort_by(.created_at, .id)[]
  | {id, created_at,
     live: ($live[.workflow_id | tostring] == true),
     path: ((.path // "unknown") | gsub("[^A-Za-z0-9._/@-]"; "_"))}' > "$work/deletable.jsonl"

total="$(wc -l < "$work/deletable.jsonl" | tr -d ' ')"
listed="$(wc -l < "$work/runs.jsonl" | tr -d ' ')"
head -n "$MAX_DELETIONS" "$work/deletable.jsonl" > "$work/batch.jsonl"
jq -r '[.id, .created_at[0:10], .path, .live] | @tsv' "$work/batch.jsonl" > "$work/batch.tsv"

policy="Runs created before ${cutoff} (${OLDER_THAN_DAYS} days), except the ${KEEP_RUNS} most recent of each workflow and the runs of the open pull requests"
if [[ -n "$GITHUB_SHA" ]]; then
  policy+=" and of ${GITHUB_SHA:0:7}"
fi
echo "${policy}: ${total} to delete, at most ${MAX_DELETIONS} in this run."
if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run: nothing is deleted."
fi
count=0
while IFS=$'\t' read -r id day path live; do
  [[ "$id" =~ ^[0-9]+$ ]] || fail "unexpected run id '$id'"
  what="run $id of $day, $path"
  [[ "$live" == true ]] || what+=" (workflow file deleted)"
  if [[ "$DRY_RUN" == true ]]; then
    echo "Would delete $what"
  else
    if ((count > 0)); then
      sleep "$DELETE_INTERVAL"
    fi
    status="$(api "$work/delete.json" -X DELETE "${api_root}/actions/runs/${id}")"
    case "$status" in
      204) echo "Deleted $what" ;;
      404) echo "Already gone: $what" ;;
      *) fail "GitHub answered $status deleting $what: $(message "$work/delete.json")" ;;
    esac
  fi
  count=$((count + 1))
done < "$work/batch.tsv"
remaining=$((total - count))

output() {
  printf '%s=%s\n' "$1" "$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
  fi
}
output deleted "$count"
output remaining "$remaining"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    title='Workflow runs cleanup (dry run)' verb='would be deleted'
  else
    title='Workflow runs cleanup' verb='deleted'
  fi
  {
    printf '### %s\n\n' "$title"
    printf '%s: **%s %s**.\n' "$policy" "$count" "$verb"
    if ((count > 0)); then
      printf '\n| Workflow | Runs |\n| -------- | ---: |\n'
      jq -rs 'group_by(.path) | map({path: .[0].path, live: .[0].live, n: length}) | sort_by(-.n, .path)[]
        | "| `\(.path)`\(if .live then "" else " (workflow file deleted)" end) | \(.n) |"' "$work/batch.jsonl"
    fi
    if ((remaining > 0)); then
      printf '\n%s more left for the next run (max-deletions: %s).\n' "$remaining" "$MAX_DELETIONS"
    fi
    if ((listed >= 1000)); then
      printf '\nGitHub lists 1,000 runs per query at most: the next run looks further.\n'
    fi
  } >> "$GITHUB_STEP_SUMMARY"
fi
