#!/usr/bin/env bash
# Ensure relative links in docs/ don't escape the docs/ directory.
# Links to files outside docs/ must use absolute GitHub URLs.
#
# Modes
#   prek / pre-commit : staged files are passed as arguments
#   CI / standalone   : no arguments → discovers all docs/**/*.md
set -euo pipefail

errors=0

if [[ $# -gt 0 ]]; then
  files=("$@")
else
  mapfile -t files < <(find docs -name "*.md" -type f 2>/dev/null | sort || true)
fi

for file in "${files[@]+"${files[@]}"}"; do
  file="${file#./}"
  [[ "$file" =~ ^docs/.*\.md$ ]] || continue

  # Depth of file within docs/ (docs/a.md → 0, docs/dir/a.md → 1, …)
  rel="${file#docs/}"
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
      echo "ERROR: $file: '$link' escapes docs/ (file depth=$depth, link goes up $ups level(s))"
      echo "       Replace with an absolute GitHub URL."
      (( errors++ )) || true
    fi
  done < <(grep -oE '\]\([^)]+\)' "$file" | tr -d '()]' | grep -E '^\.\.' || true)
done

if (( errors > 0 )); then
  echo ""
  echo "$errors link(s) escape docs/. Use absolute GitHub URLs for files outside docs/."
  exit 1
fi
exit 0
