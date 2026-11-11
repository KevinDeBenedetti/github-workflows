#!/usr/bin/env bash
# Delete the old workflow runs of a repository, with their logs and artifacts,
# and keep the recent ones. Optionally delete the old artifacts of the runs
# kept as well: artifacts count against the account's Actions storage for
# every hour they exist, runs and logs do not.
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
# With ARTIFACTS_OLDER_THAN_DAYS above 0, an artifact is also deleted on its
# own, its run and the run's logs staying, when all of these hold:
#   - it has not expired yet;
#   - it was created before its own cutoff day, ARTIFACTS_OLDER_THAN_DAYS days
#     ago (UTC);
#   - its run is completed: a later job of a run still going, such as a
#     deployment waiting for an approval, may still download it.
# Whether the rules above keep its run does not matter: the KEEP_RUNS most
# recent runs and the runs of the open pull requests and of GITHUB_SHA lose
# their old artifacts too.
#
# The artifacts go first, then the runs, each oldest first: at most
# MAX_DELETIONS deletions of both kinds per run, DELETE_INTERVAL seconds
# apart. A GITHUB_TOKEN may send 1,000 REST requests an hour per repository,
# and GitHub asks for a pause between deletions. GitHub lists at most 1,000
# runs per query, so a larger backlog takes several runs.
#
# Talks to the REST API with curl, the token in a header file, never on a
# command line: self-hosted runner images often ship no GitHub CLI.
#
# Env: KEEP_RUNS          most recent runs kept per workflow, 0-100 (default 10)
#      OLDER_THAN_DAYS    age in days before a run can go, 1 or more (default 30)
#      ARTIFACTS_OLDER_THAN_DAYS
#                         age in days before an artifact goes on its own,
#                         0-36500; 0 turns it off (default 0)
#      MAX_DELETIONS      deletions at most in one run, artifacts and runs
#                         together, 1-1000 (default 500)
#      DRY_RUN            true: print what would be deleted, delete nothing
#                         (default false)
#      DELETE_INTERVAL    seconds between two deletions (default 1)
#      GITHUB_TOKEN       actions write, pull-requests read (required)
#      GITHUB_REPOSITORY  owner/name (required)
#      GITHUB_SHA         a commit whose runs are kept (optional)
#      GITHUB_API_URL     REST API root, set by the runner
#                         (default: https://api.github.com)
# Outputs (GITHUB_OUTPUT, and stdout): deleted and remaining (runs),
# artifacts-deleted and artifacts-bytes-freed (the artifacts deleted on their
# own). The job summary counts the runs deleted per workflow and the space
# the artifacts freed.
set -euo pipefail

KEEP_RUNS="${KEEP_RUNS:-10}"
OLDER_THAN_DAYS="${OLDER_THAN_DAYS:-30}"
ARTIFACTS_OLDER_THAN_DAYS="${ARTIFACTS_OLDER_THAN_DAYS:-0}"
MAX_DELETIONS="${MAX_DELETIONS:-500}"
DRY_RUN="${DRY_RUN:-false}"
DELETE_INTERVAL="${DELETE_INTERVAL:-1}"
# Pages of artifacts read at most, 100 artifacts each. GitHub lists the newest
# first, the expired ones included.
ARTIFACT_PAGES=100

fail() {
  echo "::error::$*" >&2
  exit 1
}

# Whole numbers within bounds, stored without leading zeros.
for setting in "KEEP_RUNS 0 100" "OLDER_THAN_DAYS 1 36500" "ARTIFACTS_OLDER_THAN_DAYS 0 36500" \
  "MAX_DELETIONS 1 1000" "DELETE_INTERVAL 0 60"; do
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

# list PATH ITEMS FIELDS OUT [PAGES]: FIELDS of each element of the ITEMS
# array, page after page of PATH, one JSON value per line in OUT. PAGES pages
# at most, ten by default: GitHub ends a filtered query at 1,000 results.
list() {
  local path="$1" items="$2" fields="$3" out="$4" pages="${5:-10}" page=1 sep='?' status
  if [[ "$path" == *\?* ]]; then
    sep='&'
  fi
  : > "$out"
  while ((page <= pages)); do
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

# The artifacts, when they go on their own: every one GitHub lists, expired
# ones included, then the runs not completed yet, asked only when an old
# artifact could be theirs.
artifacts_cutoff=""
: > "$work/artifacts.jsonl"
: > "$work/active.jsonl"
if ((ARTIFACTS_OLDER_THAN_DAYS > 0)); then
  artifacts_cutoff="$(jq -rn --argjson days "$ARTIFACTS_OLDER_THAN_DAYS" '(now | floor) - $days * 86400 | strftime("%Y-%m-%d")')"
  list /actions/artifacts .artifacts '{id, name, size_in_bytes, created_at, expired, run: .workflow_run.id}' \
    "$work/artifacts.jsonl" "$ARTIFACT_PAGES"
  if jq -e --arg cutoff "$artifacts_cutoff" \
    'select(.expired != true and (.created_at | type) == "string" and .created_at < $cutoff)' \
    "$work/artifacts.jsonl" > /dev/null; then
    for state in queued in_progress waiting requested pending; do
      list "/actions/runs?status=${state}" .workflow_runs .id "$work/state.jsonl"
      cat "$work/state.jsonl" >> "$work/active.jsonl"
    done
  fi
fi
artifacts_listed="$(wc -l < "$work/artifacts.jsonl" | tr -d ' ')"

# The artifact rules checked here, as the run rules above. A size is only used
# as a whole number, and a name only printed with unusual characters replaced:
# it comes from a workflow file.
jq -cn \
  --slurpfile artifacts "$work/artifacts.jsonl" \
  --slurpfile active "$work/active.jsonl" \
  --arg cutoff "$artifacts_cutoff" '
  ($active | map({key: tostring, value: true}) | from_entries) as $active
  | $artifacts
  | map(select(
      (.id | type) == "number"
      and .expired != true
      and (.created_at | type) == "string" and .created_at < $cutoff
      and ($active[.run // "" | tostring] | not)))
  | unique_by(.id)
  | sort_by(.created_at, .id)[]
  | {id, created_at,
     size: (if (.size_in_bytes | type) == "number" and .size_in_bytes >= 0 then .size_in_bytes | floor else 0 end),
     run: (if (.run | type) == "number" then .run else "unknown" end),
     name: ((.name // "unknown") | tostring | gsub("[^A-Za-z0-9._/@-]"; "_"))}' > "$work/artifacts-deletable.jsonl"

# The artifacts first, then the runs, within one MAX_DELETIONS.
artifacts_total="$(wc -l < "$work/artifacts-deletable.jsonl" | tr -d ' ')"
head -n "$MAX_DELETIONS" "$work/artifacts-deletable.jsonl" > "$work/artifacts-batch.jsonl"
artifacts_batch="$(wc -l < "$work/artifacts-batch.jsonl" | tr -d ' ')"
: > "$work/batch.jsonl"
if ((MAX_DELETIONS > artifacts_batch)); then
  head -n "$((MAX_DELETIONS - artifacts_batch))" "$work/deletable.jsonl" > "$work/batch.jsonl"
fi
jq -r '[.id, .created_at[0:10], .size, .run, .name] | @tsv' "$work/artifacts-batch.jsonl" > "$work/artifacts-batch.tsv"
jq -r '[.id, .created_at[0:10], .path, .live] | @tsv' "$work/batch.jsonl" > "$work/batch.tsv"

policy="Runs created before ${cutoff} (${OLDER_THAN_DAYS} days), except the ${KEEP_RUNS} most recent of each workflow and the runs of the open pull requests"
if [[ -n "$GITHUB_SHA" ]]; then
  policy+=" and of ${GITHUB_SHA:0:7}"
fi
artifacts_policy="Artifacts created before ${artifacts_cutoff} (${ARTIFACTS_OLDER_THAN_DAYS} days) of any completed run"
if ((ARTIFACTS_OLDER_THAN_DAYS > 0)); then
  echo "${artifacts_policy}: ${artifacts_total} to delete."
  echo "${policy}: ${total} to delete."
  echo "At most ${MAX_DELETIONS} deletions in this run, the artifacts first."
else
  echo "${policy}: ${total} to delete, at most ${MAX_DELETIONS} in this run."
fi
if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run: nothing is deleted."
fi

# mb BYTES: BYTES in megabytes of 1,048,576 bytes, one decimal.
mb() {
  local tenths=$(((10#$1 * 10 + 524288) / 1048576))
  printf '%d.%d' $((tenths / 10)) $((tenths % 10))
}

# remove KIND ID WHAT: asks GitHub to delete the KIND (runs or artifacts) ID,
# DELETE_INTERVAL seconds after the deletion before it, whatever its kind.
# Sets removed to true when GitHub deleted it, to false when it was already
# gone; any other answer stops the run.
requests=0
removed=false
remove() {
  local status
  if ((requests > 0)); then
    sleep "$DELETE_INTERVAL"
  fi
  requests=$((requests + 1))
  status="$(api "$work/delete.json" -X DELETE "${api_root}/actions/$1/$2")"
  case "$status" in
    204)
      echo "Deleted $3"
      removed=true
      ;;
    404)
      echo "Already gone: $3"
      removed=false
      ;;
    *) fail "GitHub answered $status deleting $3: $(message "$work/delete.json")" ;;
  esac
}

# An artifact already gone freed nothing: it is not counted.
artifacts_deleted=0
bytes_freed=0
while IFS=$'\t' read -r id day size run name; do
  [[ "$id" =~ ^[0-9]+$ && "$size" =~ ^[0-9]{1,15}$ ]] || fail "unexpected artifact id '$id' or size '$size'"
  what="artifact $id of $day, $name ($(mb "$size") MB, run $run)"
  if [[ "$DRY_RUN" == true ]]; then
    echo "Would delete $what"
    removed=true
  else
    remove artifacts "$id" "$what"
  fi
  if [[ "$removed" == true ]]; then
    artifacts_deleted=$((artifacts_deleted + 1))
    bytes_freed=$((bytes_freed + 10#$size))
  fi
done < "$work/artifacts-batch.tsv"
artifacts_remaining=$((artifacts_total - artifacts_batch))

count=0
while IFS=$'\t' read -r id day path live; do
  [[ "$id" =~ ^[0-9]+$ ]] || fail "unexpected run id '$id'"
  what="run $id of $day, $path"
  [[ "$live" == true ]] || what+=" (workflow file deleted)"
  if [[ "$DRY_RUN" == true ]]; then
    echo "Would delete $what"
  else
    remove runs "$id" "$what"
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
output artifacts-deleted "$artifacts_deleted"
output artifacts-bytes-freed "$bytes_freed"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    title='Workflow runs cleanup (dry run)' verb='would be deleted' freed='would be freed'
  else
    title='Workflow runs cleanup' verb='deleted' freed='freed'
  fi
  {
    printf '### %s\n\n' "$title"
    if ((ARTIFACTS_OLDER_THAN_DAYS > 0)); then
      printf '%s: **%s %s, %s MB %s**.\n' "$artifacts_policy" "$artifacts_deleted" "$verb" "$(mb "$bytes_freed")" "$freed"
      if ((artifacts_remaining > 0)); then
        printf '%s more left for the next run (max-deletions: %s).\n' "$artifacts_remaining" "$MAX_DELETIONS"
      fi
      if ((artifacts_listed >= ARTIFACT_PAGES * 100)); then
        printf 'GitHub lists at least %s artifacts, the newest first: older ones were not looked at.\n' "$((ARTIFACT_PAGES * 100))"
      fi
      printf '\n'
    fi
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
