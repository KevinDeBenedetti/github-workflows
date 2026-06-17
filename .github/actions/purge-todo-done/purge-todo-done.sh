#!/usr/bin/env bash
# =============================================================================
# purge-todo-done.sh — generic `prepare-commit-msg` hook that flushes completed
# tasks out of TODO.md at commit time.
#
# When TODO.md is part of the commit, it strips every checked item (`- [x] …`)
# from the "✅ Fait" (Done) section and re-stages the file, so done tasks don't
# pile up in the tracker — the record lives in git history and the commit message
# instead. The "## ✅ Fait" heading itself is kept; only its `- [x]` lines go.
#
# Repo-agnostic: drop it into any repo via prek/pre-commit (hook id
# `purge-todo-done`). It runs at `prepare-commit-msg`, which — unlike `pre-commit`
# — does NOT trigger the framework's "files were modified by this hook" abort, so
# the purge lands in the SAME commit in one action (best DX). If a given git flow
# doesn't pick up the re-stage, it degrades to leaving TODO.md modified in the
# working tree — it never blocks a commit.
#
# Fail-open by design. It is a no-op when:
#   - TODO.md is absent or not part of this commit (nothing staged for it),
#   - the commit is a merge/squash (rewriting the tracker there is surprising),
#   - the ✅ Fait section has no checked items, or anything errors.
#
# Args (prepare-commit-msg): $1 msg file, $2 source, $3 sha.
# Env: TODO_PURGE_NO=1 disable; TODO_PURGE_FILE override path (default TODO.md);
#      TODO_PURGE_HEADING substring identifying the Done heading (default "Fait").
# =============================================================================
set -u

main() {
  local source="${2:-}"

  [ "${TODO_PURGE_NO:-0}" = "1" ] && return 0
  # Don't rewrite the tracker on merges/squashes — the staged set isn't "your" work.
  case "$source" in merge|squash) return 0 ;; esac

  local todo="${TODO_PURGE_FILE:-TODO.md}"
  [ -f "$todo" ] || return 0

  # Only act when TODO.md is actually staged in THIS commit; otherwise re-staging
  # it would smuggle an unrelated change into the user's commit.
  git diff --cached --name-only -- "$todo" 2>/dev/null \
    | grep -Fxq "$todo" || return 0

  local heading="${TODO_PURGE_HEADING:-Fait}"

  # Drop `- [x] …` lines that fall under the Done heading, up to the next `## `
  # heading (or EOF). The heading line itself and everything else is preserved.
  local cleaned
  cleaned="$(awk -v h="$heading" '
    /^##[[:space:]]/ { in_done = (index($0, h) > 0) ? 1 : 0 }
    in_done && /^-[[:space:]]\[[xX]\][[:space:]]/ { next }
    { print }
  ' "$todo" 2>/dev/null)" || return 0

  # No change → nothing to do (also guards an empty awk result).
  [ -n "$cleaned" ] || return 0
  cmp -s <(printf '%s\n' "$cleaned") "$todo" && return 0

  local tmp; tmp="$(mktemp "${todo}.XXXXXX")" || return 0
  if ! printf '%s\n' "$cleaned" > "$tmp" || ! mv "$tmp" "$todo"; then
    rm -f "$tmp"
    return 0
  fi

  # Fold the purge into this commit. Failure here is non-fatal: the working-tree
  # change simply rides along with the user's next commit.
  git add -- "$todo" >/dev/null 2>&1 || true
}

main "$@" || true
exit 0
