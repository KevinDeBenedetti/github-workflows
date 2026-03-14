#!/usr/bin/env bash
# Ensure relative links in docs/ don't escape the docs/ directory.
# Links to files outside docs/ must use absolute GitHub URLs.
#
# Usage: check-docs-links.sh [file ...]  (prek passes staged files)
set -euo pipefail

errors=0

for file in "$@"; do
  # Only process markdown files under docs/
  [[ "$file" == docs/*.md || "$file" == docs/**/*.md ]] || continue

  # Depth of file within docs/ (docs/a.md → 0, docs/dir/a.md → 1, …)
  rel="${file#docs/}"
  slashes="${rel//[^\/]/}"
  depth="${#slashes}"
  # The file itself counts as one segment; its directory depth is depth-1
  # but we want "how many ../ can go up before leaving docs/", which equals
  # the number of directory separators in the path (= depth above).

  # Extract targets of relative links: ](../…) or ](./…)
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
