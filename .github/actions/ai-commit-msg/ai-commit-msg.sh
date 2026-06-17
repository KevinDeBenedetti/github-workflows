#!/usr/bin/env bash
# =============================================================================
# ai-commit-msg.sh — generic `prepare-commit-msg` hook that pre-fills the commit
# message from the STAGED DIFF using the `claude` CLI (headless `claude -p`).
#
# Repo-agnostic: drop it into any repo via prek/pre-commit (see the companion
# .pre-commit-hooks.yaml, hook id `ai-commit-msg`). On a plain `git commit` it
# asks Claude for a Conventional Commits message (title + body) built from
# `git diff --cached` and pre-fills the editor; you review/edit before the commit
# completes.
#
# Fail-open by design — it NEVER blocks a commit. It is a no-op when:
#   - a message is already present (`-m`, a -t template, an amend, a merge),
#   - nothing is staged,
#   - the `claude` CLI is missing/offline/disabled, or anything errors.
#
# Args (prepare-commit-msg): $1 msg file, $2 source, $3 sha.
# Env: AI_COMMIT_NO_AI=1 disable; AI_COMMIT_MODEL (default sonnet);
#      AI_COMMIT_TIMEOUT secs (needs timeout(1)); AI_COMMIT_MAX_CHARS (default 12000).
# =============================================================================
set -u

# Resolve the `claude` CLI. GUI Git clients (VS Code, Tower, …) launch hooks with
# a minimal PATH that does NOT include ~/.zshrc additions, so a bare `command -v
# claude` often fails there even when it works in a terminal. Fall back to common
# install locations (Homebrew, npm/bun/pnpm globals, ~/.local/bin) and let
# AI_COMMIT_CLAUDE_BIN override explicitly. Echoes the resolved path, or nothing.
resolve_claude() {
  if [ -n "${AI_COMMIT_CLAUDE_BIN:-}" ]; then
    [ -x "$AI_COMMIT_CLAUDE_BIN" ] && { printf '%s' "$AI_COMMIT_CLAUDE_BIN"; return 0; }
    return 1
  fi
  local p; p="$(command -v claude 2>/dev/null)" && { printf '%s' "$p"; return 0; }
  local c
  for c in \
    /opt/homebrew/bin/claude /usr/local/bin/claude \
    "${HOME}/.claude/local/claude" "${HOME}/.local/bin/claude" \
    "${HOME}/.bun/bin/claude" "${HOME}/.npm-global/bin/claude" \
    "${HOME}/.local/share/pnpm/claude"; do
    [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

main() {
  local msgfile="${1:-}" source="${2:-}"

  [ "${AI_COMMIT_NO_AI:-0}" = "1" ] && return 0
  [ -n "$source" ] && return 0                          # -m / merge / squash / template
  [ -n "$msgfile" ] && [ -f "$msgfile" ] || return 0
  # Don't clobber an existing message (prek may not forward $source): bail if the
  # file already has a non-blank, non-comment line.
  grep -qvE '^[[:space:]]*(#|$)' "$msgfile" && return 0
  local claude_bin; claude_bin="$(resolve_claude)" || return 0

  local diff; diff="$(git diff --cached --no-color 2>/dev/null)" || return 0
  [ -n "$diff" ] || return 0                            # nothing staged

  # Cap the payload for latency/cost; lead with the --stat for high-level context.
  # Substring expansion (not a pipe) avoids SIGPIPE under `set -o pipefail`.
  local stat; stat="$(git diff --cached --stat --no-color 2>/dev/null)"
  local combined="${stat}"$'\n\n'"${diff}"
  local payload="${combined:0:${AI_COMMIT_MAX_CHARS:-12000}}"

  # Single-quoted instructions + variable concatenation so the diff's backticks
  # and $ are NEVER evaluated (no heredoc expansion).
  local instructions prompt
  instructions='Write ONE git commit message in Conventional Commits format for the STAGED diff below.
Rules:
- First line: "<type>(optional scope): summary", imperative mood, <=72 chars
  (types: feat, fix, docs, chore, refactor, test, perf, build, ci).
- Then a blank line, then a "- " bullet body describing the notable changes
  (omit the body for a trivial one-line change).
- Base it ONLY on the diff; do not invent changes. Output ONLY the raw commit
  message: no markdown code fences, no preamble, no quotes, no commentary.

STAGED DIFF:'
  prompt="$instructions
$payload"

  local -a runner=("$claude_bin" -p "$prompt" --model "${AI_COMMIT_MODEL:-sonnet}" --strict-mcp-config)
  local out
  if command -v timeout >/dev/null 2>&1; then
    out="$(timeout "${AI_COMMIT_TIMEOUT:-60}" "${runner[@]}" 2>/dev/null)" || return 0
  elif command -v gtimeout >/dev/null 2>&1; then
    out="$(gtimeout "${AI_COMMIT_TIMEOUT:-60}" "${runner[@]}" 2>/dev/null)" || return 0
  else
    out="$("${runner[@]}" 2>/dev/null)" || return 0
  fi

  # Drop stray code-fence lines and leading blank lines; bail if nothing useful.
  out="$(printf '%s\n' "$out" | grep -v '^[[:space:]]*```' | awk 'NF{p=1} p' || true)"
  [ -n "$out" ] || return 0

  local tmp; tmp="$(mktemp "${msgfile}.XXXXXX")" || return 0
  { printf '%s\n' "$out"; cat "$msgfile"; } > "$tmp" && mv "$tmp" "$msgfile"
}

main "$@" || true
exit 0
