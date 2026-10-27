#!/usr/bin/env bash
# Print the context Claude reads to describe a pull request: the language to
# write in, the title, the commit messages, the diffstat and the diff.
#
# Lockfiles and minified or source-map files stay in the diffstat but are left
# out of the diff: they cost tokens and tell a reviewer nothing. A diff over
# MAX_DIFF_BYTES is cut at the last full line before the cap, and the context
# says so.
#
# Env: BASE_SHA, HEAD_SHA    commits to compare, the diff is BASE...HEAD (required)
#      PR_TITLE              pull request title (optional)
#      DESCRIPTION_LANGUAGE  language of the description (default: English; not
#                            LANGUAGE, which gettext reads as a locale)
#      MAX_DIFF_BYTES        size cap of the diff, in bytes (default: 100000)
# Run inside the checkout, with the history of both commits. Prints to stdout.
set -euo pipefail

: "${BASE_SHA:?BASE_SHA is required}"
: "${HEAD_SHA:?HEAD_SHA is required}"
DESCRIPTION_LANGUAGE="${DESCRIPTION_LANGUAGE:-English}"
MAX_DIFF_BYTES="${MAX_DIFF_BYTES:-100000}"
case "$MAX_DIFF_BYTES" in
  '' | *[!0-9]* | 0)
    echo "MAX_DIFF_BYTES must be a positive integer, got '${MAX_DIFF_BYTES}'" >&2
    exit 2
    ;;
esac

cd "$(git rev-parse --show-toplevel)"

# Listed in the diffstat, left out of the diff body.
EXCLUDES=(
  ':(glob,exclude)**/package-lock.json'
  ':(glob,exclude)**/npm-shrinkwrap.json'
  ':(glob,exclude)**/pnpm-lock.yaml'
  ':(glob,exclude)**/yarn.lock'
  ':(glob,exclude)**/bun.lock'
  ':(glob,exclude)**/bun.lockb'
  ':(glob,exclude)**/uv.lock'
  ':(glob,exclude)**/poetry.lock'
  ':(glob,exclude)**/Pipfile.lock'
  ':(glob,exclude)**/Cargo.lock'
  ':(glob,exclude)**/go.sum'
  ':(glob,exclude)**/composer.lock'
  ':(glob,exclude)**/Gemfile.lock'
  ':(glob,exclude)**/*.min.js'
  ':(glob,exclude)**/*.min.css'
  ':(glob,exclude)**/*.map'
)

diff_file="$(mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/pr-diff.XXXXXX")"
trap 'rm -f "$diff_file"' EXIT
git diff --no-color --no-ext-diff "${BASE_SHA}...${HEAD_SHA}" -- . "${EXCLUDES[@]}" > "$diff_file"
diff_size=$(wc -c < "$diff_file" | tr -d ' ')

printf 'Write the description in %s.\n\n' "$DESCRIPTION_LANGUAGE"
printf '<title>\n%s\n</title>\n\n' "${PR_TITLE:-}"
printf '<commits>\n'
git log --no-color --no-merges --reverse --format='* %s%n%w(0,2,2)%b' "${BASE_SHA}..${HEAD_SHA}"
printf '</commits>\n\n<diffstat>\n'
git diff --no-color --stat=200 "${BASE_SHA}...${HEAD_SHA}"
printf '</diffstat>\n\n<diff>\n'
if [ "$diff_size" -gt "$MAX_DIFF_BYTES" ]; then
  # Cut at the cap, then drop the last line, which may be partial.
  head -c "$MAX_DIFF_BYTES" "$diff_file" | sed '$d'
  printf '</diff>\n\n'
  printf 'The diff above was cut to its first %s of %s bytes: rely on the commits and the diffstat for the rest.\n' \
    "$MAX_DIFF_BYTES" "$diff_size"
else
  cat "$diff_file"
  printf '</diff>\n'
fi
