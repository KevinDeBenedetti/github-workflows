#!/usr/bin/env bash
# Detect which app directories under $APPS_DIR changed since $BASE, the change
# base the action's change-base step found, and write the result to
# $GITHUB_OUTPUT: a JSON array of the changed apps' names, whether any app
# changed, and one changed_<app> flag per app (lowercased, every character
# outside a-z and 0-9 replaced by `_`).
#
# No change base (a manual or scheduled run, or a clone holding neither the
# previous commit nor the default branch): every app counts as changed, with a
# warning, so that no app is skipped unnoticed.
#
# Environment:
#   APPS_DIR       directory holding one subdirectory per app (default "apps")
#   BASE           the change base (full SHA), empty when there is none
#   GITHUB_OUTPUT  set by the runner: changed_apps, has_changes, changed_<app>
set -euo pipefail

APPS_DIR="${APPS_DIR:-apps}"
APPS_DIR="${APPS_DIR%/}"
BASE="${BASE:-}"
out="${GITHUB_OUTPUT:-/dev/null}"

if [[ -z "$BASE" ]]; then
  echo "::warning::No change base for this run (a manual or scheduled run, or a clone holding neither the previous commit nor the default branch): every app counts as changed. On a push, check out with fetch-depth: 0 so that one of them is in the clone."
elif ! git cat-file -e "${BASE}^{commit}" 2> /dev/null; then
  echo "::error::Change base $BASE is not in the clone." >&2
  exit 1
else
  echo "Comparing against: $BASE"
fi

changed=()
if [[ -d "$APPS_DIR" ]]; then
  shopt -s nullglob
  for app_path in "$APPS_DIR"/*/; do
    app="$(basename "$app_path")"
    key="$(printf '%s' "$app" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '_')"
    changed_files=""
    if [[ -n "$BASE" ]]; then
      # A plain assignment, so that a git failure aborts through set -e
      # instead of passing as "no change".
      changed_files="$(git diff --name-only "$BASE" HEAD -- "$app_path")"
    fi
    if [[ -z "$BASE" || -n "$changed_files" ]]; then
      echo "✅ Changed: $app"
      changed+=("$app")
      echo "changed_${key}=true" >> "$out"
    else
      echo "⏭️  Unchanged: $app"
      echo "changed_${key}=false" >> "$out"
    fi
  done
else
  echo "⚠️  Directory '$APPS_DIR' not found — no apps to build"
fi

if ((${#changed[@]} > 0)); then
  changed_apps="$(printf '%s\n' "${changed[@]}" | jq -R . | jq -cs .)"
  has_changes=true
else
  changed_apps='[]'
  has_changes=false
fi
echo "changed_apps=$changed_apps" >> "$out"
echo "has_changes=$has_changes" >> "$out"
echo
echo "Summary → changed apps: $changed_apps"
