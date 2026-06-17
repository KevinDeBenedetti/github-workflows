#!/usr/bin/env bash
# =============================================================================
# ai-commit-msg-smoke.sh — MANUAL smoke test for the ai-commit-msg hook against
# the LIVE `claude` CLI (real Anthropic API call).
#
# The Bats suite (tests/ai-commit-msg.bats) covers the hook logic with a FAKE
# `claude`, so it needs no network. This script covers the one thing that can't:
# that a real `claude -p` actually returns a usable Conventional Commits message
# from a staged diff. It is NOT run in CI (no .bats, kept out of `bats tests/`)
# because CI has neither network nor `claude` credentials — run it locally.
#
# It drives the hook directly (no commit is created), prints the generated
# message, and exits non-zero if generation produced nothing or the first line
# isn't a Conventional Commits subject.
#
# Usage:
#   tests/smoke/ai-commit-msg-smoke.sh
# Honors the same env as the hook (AI_COMMIT_MODEL, AI_COMMIT_TIMEOUT, …).
# =============================================================================
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hook="${repo_root}/.github/actions/ai-commit-msg/ai-commit-msg.sh"
[ -f "$hook" ] || { echo "✗ hook not found: $hook" >&2; exit 2; }

if ! command -v claude >/dev/null 2>&1 && [ -z "${AI_COMMIT_CLAUDE_BIN:-}" ]; then
  echo "✗ \`claude\` not found on PATH and AI_COMMIT_CLAUDE_BIN unset — nothing to smoke-test." >&2
  exit 2
fi

# Use an explicit template so TMPDIR is honored on macOS too (a bare `mktemp -d`
# there ignores TMPDIR and uses the Darwin user temp dir).
work="$(mktemp -d "${TMPDIR:-/tmp}/ai-commit-smoke.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cd "$work"

git init -q
git config user.email smoke@example.com
git config user.name smoke

# A small but realistic staged change for claude to describe.
mkdir -p src
cat > src/greeting.js <<'JS'
export function greet(name) {
  return `Hello, ${name}!`;
}
JS
git add src/greeting.js

msg="$work/COMMIT_EDITMSG"
: > "$msg"

echo "→ Running ai-commit-msg against the live claude CLI (model: ${AI_COMMIT_MODEL:-sonnet})…"
bash "$hook" "$msg" "" ""

echo "──────── generated COMMIT_EDITMSG ────────"
cat "$msg"
echo "──────────────────────────────────────────"

first_line="$(grep -vE '^[[:space:]]*(#|$)' "$msg" | head -n 1 || true)"
if [ -z "$first_line" ]; then
  echo "✗ FAIL: no message was generated (network down, auth missing, or claude errored)." >&2
  exit 1
fi
if ! printf '%s' "$first_line" \
  | grep -qE '^(feat|fix|docs|chore|refactor|test|perf|build|ci)(\(.+\))?!?: .+'; then
  echo "✗ FAIL: first line is not a Conventional Commits subject: $first_line" >&2
  exit 1
fi

echo "✓ PASS: generated a Conventional Commits subject → $first_line"
