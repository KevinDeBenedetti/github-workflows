#!/usr/bin/env bash
# Write a pull request description with Claude Code in headless mode
# (`claude -p`), from the context printed by collect-context.sh.
#
# Claude gets no tool at all and runs from an empty working directory with an
# empty configuration directory: no hook, MCP server, CLAUDE.md or setting of
# the checked-out repository can load (`claude -p` would otherwise run them),
# and the diff can only shape the text Claude writes. ANTHROPIC_API_KEY and
# ANTHROPIC_AUTH_TOKEN are unset for the call: either would take precedence
# over the subscription token.
#
# Env: CLAUDE_CODE_OAUTH_TOKEN  token from `claude setup-token` (required)
#      MODEL                    model alias or full name (required)
#      EFFORT                   effort level (optional, empty: Claude Code's default)
#      CONTEXT_FILE             input, printed by collect-context.sh (required)
#      DESCRIPTION_FILE         output, the Markdown description (required)
set -euo pipefail

: "${CLAUDE_CODE_OAUTH_TOKEN:?CLAUDE_CODE_OAUTH_TOKEN is required}"
: "${MODEL:?MODEL is required}"
: "${CONTEXT_FILE:?CONTEXT_FILE is required}"
: "${DESCRIPTION_FILE:?DESCRIPTION_FILE is required}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/pr-description.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir "$work/cwd" "$work/config"

args=(
  -p "Write the pull request description."
  --model "$MODEL"
  --system-prompt-file "$here/system-prompt.md"
  --output-format json
  --max-turns 1
  --no-session-persistence
  --setting-sources user
  --strict-mcp-config
  --tools ""
)
if [ -n "${EFFORT:-}" ]; then
  args+=(--effort "$EFFORT")
fi

status=0
(
  cd "$work/cwd"
  exec env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN \
    CLAUDE_CONFIG_DIR="$work/config" \
    CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 \
    DISABLE_AUTOUPDATER=1 \
    DISABLE_UPDATES=1 \
    DISABLE_TELEMETRY=1 \
    DISABLE_ERROR_REPORTING=1 \
    claude "${args[@]}"
) < "$CONTEXT_FILE" > "$work/result.json" || status=$?

if ! jq -e 'type == "object"' "$work/result.json" > /dev/null 2>&1; then
  echo "::error::Claude Code exited with status ${status} without a JSON result."
  exit 1
fi
if [ "$status" -ne 0 ] || ! jq -e '.is_error == false and (.result | type) == "string"' "$work/result.json" > /dev/null; then
  # Flattened and stripped of '::' so the message cannot inject a workflow command.
  reason="$(jq -r '.result // .subtype // "unknown error"' "$work/result.json" | tr '\r\n' '  ' | cut -c1-300)"
  echo "::error::Claude Code failed (exit ${status}): ${reason//::/: :}"
  exit 1
fi

jq -r '.result' "$work/result.json" > "$DESCRIPTION_FILE"
if ! grep -q '[^[:space:]]' "$DESCRIPTION_FILE"; then
  echo "::error::Claude Code returned an empty description."
  exit 1
fi
echo "Description written with ${MODEL}."
