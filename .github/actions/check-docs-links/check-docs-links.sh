#!/usr/bin/env bash
# Ensure relative links in the docs directory don't escape it.
# Links to files outside the docs directory must use absolute GitHub URLs.
#
# Docs directory: $DOCS_DIR (default "docs") — set by the action's
# `docs-directory` input so callers with a non-default docs folder are checked
# against the right root.
#
# Every relative link target is normalised segment by segment (".", "..",
# "a/../b", "./../x"), so a link escapes whenever its resolved path leaves the
# docs directory — not only when it happens to start with "../". Links inside
# fenced code blocks are ignored (they are examples, not navigation).
#
# Modes
#   prek / pre-commit : staged files are passed as arguments
#   CI / standalone   : no arguments → discovers all $DOCS_DIR/**/*.md
set -euo pipefail

DOCS_DIR="${DOCS_DIR:-docs}"
DOCS_DIR="${DOCS_DIR%/}"

errors=0

# escapes <dir-of-file-relative-to-docs> <link-target>
# Returns 0 when the target resolves outside the docs directory. Pure bash
# (no `realpath -m`, which macOS lacks) so the prek hook runs locally too.
escapes() {
  local base="$1" target="$2"
  local -a stack=() parts=()
  local seg
  if [[ -n "$base" ]]; then
    IFS='/' read -ra parts <<< "$base"
    for seg in "${parts[@]}"; do
      [[ -n "$seg" ]] && stack+=("$seg")
    done
  fi
  IFS='/' read -ra parts <<< "$target"
  for seg in "${parts[@]}"; do
    case "$seg" in
      ''|.) ;;
      ..)
        if (( ${#stack[@]} == 0 )); then
          return 0
        fi
        unset 'stack[${#stack[@]}-1]'
        ;;
      *) stack+=("$seg") ;;
    esac
  done
  return 1
}

if [[ $# -gt 0 ]]; then
  files=("$@")
else
  mapfile -t files < <(find "$DOCS_DIR" -name "*.md" -type f 2>/dev/null | sort || true)
fi

for file in "${files[@]+"${files[@]}"}"; do
  file="${file#./}"
  [[ "$file" == "$DOCS_DIR"/*.md ]] || continue

  # Directory of the file, relative to the docs dir ("" for top-level files).
  rel="${file#"$DOCS_DIR"/}"
  base=""
  [[ "$rel" == */* ]] && base="${rel%/*}"

  in_fence=0
  lineno=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    if [[ "$line" =~ ^[[:space:]]*(\`\`\`|~~~) ]]; then
      in_fence=$(( 1 - in_fence ))
      continue
    fi
    (( in_fence )) && continue

    # Every inline link/image target on the line: ](target) or ](target "title")
    while IFS= read -r link; do
      [[ -n "$link" ]] || continue
      target="${link#](}"
      target="${target%)}"
      target="${target#<}"
      target="${target%%[[:space:]]*}"   # drop an optional "title"
      target="${target%>}"
      target="${target%%#*}"             # drop #anchor
      target="${target%%\?*}"            # drop ?query
      [[ -n "$target" ]] || continue
      # Absolute URLs, site-absolute paths and other schemes are fine.
      [[ "$target" =~ ^[a-zA-Z][a-zA-Z0-9+.-]*: || "$target" == /* ]] && continue

      if escapes "$base" "$target"; then
        echo "ERROR: $file:$lineno: '$target' escapes $DOCS_DIR/"
        echo "       Replace with an absolute GitHub URL."
        errors=$((errors + 1))
      fi
    done < <(grep -oE '\]\([^)]+\)' <<< "$line" || true)
  done < "$file"
done

if (( errors > 0 )); then
  echo ""
  echo "$errors link(s) escape $DOCS_DIR/. Use absolute GitHub URLs for files outside $DOCS_DIR/."
  exit 1
fi
exit 0
