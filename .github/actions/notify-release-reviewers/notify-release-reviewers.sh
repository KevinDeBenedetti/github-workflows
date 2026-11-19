#!/usr/bin/env bash
# Request a review on the open release PR(s) from each listed user who has
# never been asked to review it, so each user gets one GitHub notification per
# release PR, with no @mention comment on top.
#
# The PRs: release-please's `prs` output when it created or updated one this
# run; otherwise the open PRs carrying the pending label, on BASE_BRANCH — an
# untouched release PR may still need its first notification (notify-reviewers
# added after it opened, or a failed earlier attempt).
#
# "Asked" means any review_requested event on the PR's timeline, case aside:
# from an earlier run, or from GitHub itself through CODEOWNERS. A user who
# has reviewed or was removed since is not asked again.
#
# Never fails: it runs after the release, and a failed step would keep the
# alias tags from moving. Each problem is a ::warning:: instead.
#
# Env: REVIEWERS      comma-separated logins
#      PRS            release-please's prs output (JSON array), may be empty
#      PENDING_LABEL  release-please's pending label
#      BASE_BRANCH    base branch of the release PR, empty for any
#      GITHUB_REPOSITORY, GH_TOKEN
set -uo pipefail

warn() { echo "::warning::$*"; }

ERR=$(mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/notify.XXXXXX")
trap 'rm -f "$ERR"' EXIT
# error: the last call's stderr, on one line.
error() { tr -s '\n' ' ' < "$ERR" | sed 's/ *$//'; }

USERS=()
IFS=',' read -ra ENTRIES <<< "${REVIEWERS:-}"
for u in "${ENTRIES[@]}"; do
  u="$(echo "$u" | xargs)"
  [ -n "$u" ] || continue
  if ! [[ $u =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$ ]]; then
    warn "notify-reviewers: '$u' is not a GitHub login, skipping it"
    continue
  fi
  # Once each, case aside.
  printf '%s\n' "${USERS[@]}" | grep -qixF -- "$u" || USERS+=("$u")
done
if [ "${#USERS[@]}" -eq 0 ]; then
  echo "ℹ️ No reviewer to notify"
  exit 0
fi

NUMBERS=
FROM_LABEL=true
if [ -n "${PRS:-}" ] && [ "$PRS" != "null" ]; then
  if NUMBERS=$(jq -er 'if type == "array" then .[].number else error end' <<< "$PRS" 2> /dev/null); then
    FROM_LABEL=false
  elif [ "$(jq -r 'if type == "array" then length else -1 end' <<< "$PRS" 2> /dev/null)" = 0 ]; then
    NUMBERS='' FROM_LABEL=false
  else
    warn "release-please's prs output is not a JSON array of pull requests: looking the PR up by its label"
  fi
fi
if [ "$FROM_LABEL" = true ]; then
  BASE_ARGS=()
  [ -z "${BASE_BRANCH:-}" ] || BASE_ARGS=(--base "$BASE_BRANCH")
  if ! NUMBERS=$(gh pr list \
    --repo "$GITHUB_REPOSITORY" \
    --label "$PENDING_LABEL" \
    --state open \
    "${BASE_ARGS[@]}" \
    --json number --jq '.[].number' 2> "$ERR"); then
    warn "Could not list the open release PRs labelled '$PENDING_LABEL': $(error)"
    exit 0
  fi
fi
LISTED=$(xargs <<< "$NUMBERS")
echo "ℹ️ Release PRs to notify: ${LISTED:-none}"

for pr in $NUMBERS; do
  [[ $pr =~ ^[0-9]+$ ]] || continue
  # Every login ever asked to review the PR, by anyone.
  if ! ASKED=$(gh api --paginate \
    "repos/${GITHUB_REPOSITORY}/issues/${pr}/timeline" \
    --jq '.[] | select(.event == "review_requested") | .requested_reviewer.login // empty' 2> "$ERR"); then
    warn "Could not read the timeline of PR #$pr, skipping it: $(error)"
    continue
  fi
  MISSING=()
  for u in "${USERS[@]}"; do
    if grep -qixF -- "$u" <<< "$ASKED"; then
      echo "ℹ️ $u was already asked to review PR #$pr, skipping"
    else
      MISSING+=("$u")
    fi
  done
  [ "${#MISSING[@]}" -gt 0 ] || continue
  LIST="$(IFS=','; echo "${MISSING[*]}")"
  echo "ℹ️ Requesting review from $LIST on PR #$pr"
  gh pr edit "$pr" --repo "$GITHUB_REPOSITORY" --add-reviewer "$LIST" 2> "$ERR" ||
    warn "Could not request a review from $LIST on PR #$pr: $(error)"
done
exit 0
