#!/usr/bin/env bash
# Run actionlint on the workflow files of PATHS.
#
# PATHS is a space-separated list of files, directories and globs
# (.github/workflows/*.yml). A directory stands for every *.yml and *.yaml
# file under it. An entry that matches nothing fails: a typo must not shrink
# what is checked.
#
# FLAGS are split like a shell command line: `-ignore 'SC2086'` and
# `-ignore "a b"` pass one pattern each. An unmatched quote fails.
#
# Env: PATHS   (default .github/workflows/)
#      FLAGS   extra actionlint flags (default none)
# Needs python3 to split FLAGS (on the runner already: install-tool reads its
# manifest with it).
set -euo pipefail

PATHS="${PATHS-.github/workflows/}"
FLAGS="${FLAGS:-}"

fail() {
  echo "::error::$*"
  exit 1
}

ARGS=()
if [ -n "$FLAGS" ]; then
  # NUL-separated: an argument may hold any character but NUL.
  split="$(mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/actionlint-flags.XXXXXX")"
  trap 'rm -f "$split"' EXIT
  python3 -c '
import shlex, sys
try:
    words = shlex.split(sys.argv[1])
except ValueError as e:
    sys.exit(f"cannot split the flags: {e}")
sys.stdout.write("".join(w + "\0" for w in words))
' "$FLAGS" > "$split" || fail "actionlint flags must be a shell command line, not '$FLAGS'"
  while IFS= read -r -d '' word; do ARGS+=("$word"); done < "$split"
fi

FILES=()
# Space-separated on purpose, each entry glob-expanded; nullglob, so that a
# glob matching nothing is caught below rather than passed as is.
shopt -s nullglob
read -ra ENTRIES <<< "$PATHS"
((${#ENTRIES[@]})) || fail "paths is empty: nothing to check"
for entry in "${ENTRIES[@]}"; do
  # shellcheck disable=SC2206 # the glob expansion is the point.
  matches=($entry)
  ((${#matches[@]})) || fail "paths entry '$entry' matches no file or directory"
  for p in "${matches[@]}"; do
    if [ -d "$p" ]; then
      while IFS= read -r -d '' f; do
        FILES+=("$f")
      done < <(find "$p" -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 | sort -z)
    elif [ -e "$p" ]; then
      FILES+=("$p")
    else
      fail "paths entry '$entry' matches no file or directory"
    fi
  done
done
shopt -u nullglob

((${#FILES[@]})) || fail "no workflow file under '$PATHS'"
actionlint ${ARGS[@]+"${ARGS[@]}"} "${FILES[@]}"
