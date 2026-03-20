#!/usr/bin/env bash
# Detect unescaped Vue template interpolations {{ }} in docs/ markdown files.
#
# VitePress compiles every Markdown file as a Vue SFC. Any {{ expr }} outside
# a fenced code block (``` ... ```) or a v-pre wrapper is evaluated at SSR time,
# which causes build errors like:
#   TypeError: Cannot read properties of undefined (reading 'SOMEVAR')
#
# Safe patterns (not flagged):
#   - Inside fenced code blocks (``` ... ``` or ~~~ ... ~~~)
#   - Lines containing a v-pre attribute (<code v-pre>, <span v-pre>, ::: v-pre)
#
# Fix unescaped occurrences with:
#   <code v-pre>${{ expr }}</code>    — inline code in text or tables
#   <span v-pre>{{ expr }}</span>     — plain inline text
#   ::: v-pre / ::: block            — multi-line content
#
# Modes
#   prek / pre-commit : staged .md files are passed as arguments
#   CI / standalone   : no arguments → discovers all docs/**/*.md

set -euo pipefail

errors=0
checked=0

check_file() {
  local file="$1"
  local in_code_block=0
  local in_vpre_block=0
  local lineno=0

  while IFS= read -r line; do
    lineno=$((lineno + 1))

    # Toggle fenced code block (``` or ~~~)
    if [[ "$line" =~ ^[[:space:]]*'```' ]] || [[ "$line" =~ ^[[:space:]]*'~~~' ]]; then
      if (( in_code_block )); then
        in_code_block=0
      else
        in_code_block=1
      fi
    fi

    # Toggle ::: v-pre block
    if [[ "$line" =~ ^:::[[:space:]]*v-pre ]]; then
      in_vpre_block=1
    elif [[ "$line" =~ ^::: ]] && (( in_vpre_block )); then
      in_vpre_block=0
    fi

    # Skip lines inside safe contexts
    (( in_code_block || in_vpre_block )) && continue

    # Skip lines where {{ }} is wrapped in a v-pre element
    [[ "$line" == *'v-pre'* ]] && continue

    # Flag any unescaped {{ }} remaining on this line
    if [[ "$line" == *'{{'*'}}'* ]]; then
      echo "ERROR: $file:$lineno: $line" >&2
      errors=$((errors + 1))
    fi
  done < "$file"

  checked=$((checked + 1))
}

if [[ $# -gt 0 ]]; then
  for f in "$@"; do
    [[ "$f" == *.md ]] && check_file "$f"
  done
else
  while IFS= read -r -d '' f; do
    check_file "$f"
  done < <(find docs -name '*.md' -type f -print0 2>/dev/null | sort -z)
fi

if (( errors > 0 )); then
  echo "" >&2
  echo "✖ $errors unescaped Vue interpolation(s) found — VitePress SSR build will fail." >&2
  echo "  Fix options:" >&2
  echo "    Inline code : <code v-pre>\${{ expr }}</code>" >&2
  echo "    Inline text : <span v-pre>{{ expr }}</span>" >&2
  echo "    Block       : ::: v-pre / {{ expr }} / :::" >&2
  exit 1
fi

echo "✔ Checked $checked file(s) — no unescaped Vue interpolations."
exit 0
