#!/usr/bin/env bash
# Validate commit messages against Conventional Commits 1.0.0
# (https://www.conventionalcommits.org/en/v1.0.0/) plus the house rules used
# with release-please here:
#   - header: <type>(<optional scope>)<optional !>: <summary>
#   - <type> ∈ feat fix perf revert deps docs style chore test build ci
#     ('refactor' is a house ban: use 'chore' for a refactor with no
#     user-facing effect)
#   - header ≤ 100 characters (commitlint header-max-length default)
#   - body, when present, starts after one blank line
#
# Dual-mode:
#   check-commit-msg.sh <msg-file>…   prek / pre-commit `commit-msg` stage
#   COMMIT_RANGE=base..head check-commit-msg.sh
#                                     CI: every non-merge commit in the range
set -euo pipefail

TYPES='feat|fix|perf|revert|deps|docs|style|chore|test|build|ci'
MAX_HEADER=100

# check_message <label> — reads one message on stdin; prints errors, returns 1 on failure.
check_message() {
  local label="$1" msg header second
  # Drop the comment lines git leaves in the editor buffer.
  msg=$(grep -v '^#' || true)
  header=$(printf '%s\n' "$msg" | sed -n 1p)
  second=$(printf '%s\n' "$msg" | sed -n 2p)

  # Messages git or tooling generate on its own: let them through.
  case "$header" in
    'Merge '* | 'fixup! '* | 'squash! '* | 'amend! '*) return 0 ;;
  esac

  local errors=()
  if [[ "$header" =~ ^refactor(\(|!|:) ]]; then
    errors+=("'refactor' is not used here — use 'chore' for a refactor with no user-facing effect")
  elif ! [[ "$header" =~ ^($TYPES)(\([^()[:space:]][^()]*\))?!?:\ [^[:space:]] ]]; then
    errors+=("header must be '<type>(<scope>)<!>: <summary>' with <type> one of: ${TYPES//|/, }")
  fi
  if [ "${#header}" -gt "$MAX_HEADER" ]; then
    errors+=("header is ${#header} characters (max $MAX_HEADER)")
  fi
  if [ -n "$second" ]; then
    errors+=("the body must start after one blank line")
  fi

  [ "${#errors[@]}" -eq 0 ] && return 0
  printf '✗ %s: %s\n' "$label" "$header"
  printf '    - %s\n' "${errors[@]}"
  return 1
}

failed=0
if [ "$#" -gt 0 ]; then
  for file in "$@"; do
    check_message "commit message" < "$file" || failed=1
  done
elif [ -n "${COMMIT_RANGE:-}" ]; then
  while IFS= read -r sha; do
    git log -1 --format=%B "$sha" | check_message "${sha:0:7}" || failed=1
  done < <(git rev-list --no-merges "$COMMIT_RANGE")
else
  echo "usage: check-commit-msg.sh <msg-file>… | COMMIT_RANGE=base..head check-commit-msg.sh" >&2
  exit 2
fi

if [ "$failed" -ne 0 ]; then
  echo
  echo "Commit messages must follow Conventional Commits: https://www.conventionalcommits.org/en/v1.0.0/"
  exit 1
fi
