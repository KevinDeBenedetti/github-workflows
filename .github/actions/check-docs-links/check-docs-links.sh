#!/usr/bin/env bash
# Ensure relative links in the docs directory don't escape it.
# Links to files outside the docs directory must use absolute GitHub URLs.
#
# Docs directory: $DOCS_DIR (default "docs") — set by the action's
# `docs-directory` input so callers with a non-default docs folder are checked
# against the right root.
#
# Modes
#   prek / pre-commit : staged files are passed as arguments
#   CI / standalone   : no arguments → discovers all $DOCS_DIR/**/*.md
set -euo pipefail

DOCS_DIR="${DOCS_DIR:-docs}"
DOCS_DIR="${DOCS_DIR%/}"

errors=0

if [[ $# -gt 0 ]]; then
  files=("$@")
else
  mapfile -t files < <(find "$DOCS_DIR" -name "*.md" -type f 2>/dev/null | sort || true)
fi

for file in "${files[@]+"${files[@]}"}"; do
  file="${file#./}"
  [[ "$file" == "$DOCS_DIR"/*.md ]] || continue

  # Depth of file within the docs dir ($DOCS_DIR/a.md → 0, $DOCS_DIR/dir/a.md → 1, …)
  rel="${file#"$DOCS_DIR"/}"
  slashes="${rel//[^\/]/}"
  depth="${#slashes}"

  while IFS= read -r link; do
    ups=0
    rest="$link"
    while [[ "$rest" == ../* || "$rest" == ".." ]]; do
      (( ups++ )) || true
      [[ "$rest" == ".." ]] && break
      rest="${rest#../}"
    done

    if (( ups > depth )); then
      echo "ERROR: $file: '$link' escapes $DOCS_DIR/ (file depth=$depth, link goes up $ups level(s))"
      echo "       Replace with an absolute GitHub URL."
      (( errors++ )) || true
    fi
  done < <(grep -oE '\]\([^)]+\)' "$file" | tr -d '()]' | grep -E '^\.\.' || true)
done

if (( errors > 0 )); then
  echo ""
  echo "$errors link(s) escape $DOCS_DIR/. Use absolute GitHub URLs for files outside $DOCS_DIR/."
  exit 1
fi
exit 0
