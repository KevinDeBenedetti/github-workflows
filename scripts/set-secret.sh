#!/usr/bin/env bash
# Set one Actions secret to the same value in several repositories: a personal
# account has no secret shared between repositories, so a token every caller of
# a workflow needs (CLAUDE_CODE_OAUTH_TOKEN for pr-description.yml) is set in
# each of them, and again when it expires.
#
#   scripts/set-secret.sh NAME [REPO...]
#
# NAME   the secret's name.
# REPO   owner/name, or a bare name under this repository's owner. With none:
#        this repository and each one in its PROPAGATE_REPOSITORIES variable
#        (one per line, an optional `:branch` suffix ignored).
#
# The value is the first line of stdin, never an argument: piped
# (`pbpaste | scripts/set-secret.sh NAME`), or typed at a prompt that does not
# echo it. It reaches gh on stdin too, so it is on no command line.
#
# Exit: 0 every repository set, 1 an empty value or a repository that failed
# (the others are still set), 2 a bad argument.
set -uo pipefail

usage() {
  echo "usage: set-secret.sh NAME [REPO...]" >&2
  exit 2
}

[ "$#" -ge 1 ] || usage
NAME="$1"
shift
[[ $NAME =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
  echo "❌ '$NAME' is not a secret name (letters, digits and _)" >&2
  exit 2
}
for repo in "$@"; do
  [[ $repo =~ ^([A-Za-z0-9][A-Za-z0-9-]*/)?[A-Za-z0-9._][A-Za-z0-9._-]*$ ]] || {
    echo "❌ '$repo' is not a repository (owner/name or name)" >&2
    exit 2
  }
done

# The value, before any call to GitHub.
if [ -t 0 ]; then
  printf 'Value of %s (not echoed): ' "$NAME" >&2
  IFS= read -rs VALUE || true
  echo >&2
else
  IFS= read -r VALUE || true
fi
if [ -z "${VALUE:-}" ]; then
  echo "❌ the value is empty: nothing was set" >&2
  exit 1
fi

if ! HERE=$(gh repo view --json nameWithOwner --jq .nameWithOwner); then
  echo "❌ could not read this repository from gh" >&2
  exit 1
fi
OWNER="${HERE%%/*}"

REPOS=("$@")
if [ "${#REPOS[@]}" -eq 0 ]; then
  REPOS=("$HERE")
  # No variable: this repository only.
  while IFS= read -r line; do
    line="$(echo "${line%%:*}" | xargs)"
    [ -z "$line" ] || REPOS+=("$line")
  done < <(gh variable get PROPAGATE_REPOSITORIES 2> /dev/null || true)
fi

ERR=$(mktemp "${TMPDIR:-/tmp}/set-secret.XXXXXX")
trap 'rm -f "$ERR"' EXIT
DONE=0
FAILED=0
for repo in "${REPOS[@]}"; do
  [[ $repo == */* ]] || repo="$OWNER/$repo"
  if printf '%s' "$VALUE" | gh secret set "$NAME" --repo "$repo" > /dev/null 2> "$ERR"; then
    echo "✅ $repo"
    DONE=$((DONE + 1))
  else
    echo "❌ $repo: $(tr -s '\n' ' ' < "$ERR" | sed 's/ *$//')"
    FAILED=$((FAILED + 1))
  fi
done
unset VALUE

if [ "$FAILED" -gt 0 ]; then
  echo "❌ $NAME set in $DONE repositories, failed in $FAILED"
  exit 1
fi
echo "✅ $NAME set in $DONE repositories"
