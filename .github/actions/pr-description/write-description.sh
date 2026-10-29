#!/usr/bin/env bash
# Write a pull request description with Claude Code in headless mode
# (`claude -p`), from the context printed by collect-context.sh.
#
# Claude gets no tool at all and runs from an empty working directory with an
# empty configuration directory: no hook, MCP server, CLAUDE.md, skill or
# setting of the checked-out repository can load (`claude -p` would otherwise
# run them), and the diff can only shape the text Claude writes. The process
# gets a minimal environment: the subscription token, Claude Code's own flags,
# and the variables a runner needs for PATH, locale, proxy and CA bundles.
# Nothing else from the job (GITHUB_TOKEN, cloud credentials, ANTHROPIC_API_KEY,
# which would take precedence over the token) reaches it.
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

# Private files: the description is written for the next step only.
umask 077

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/pr-description.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir "$work/cwd" "$work/config" "$work/home" "$work/tmp"

args=(
  -p "Write the pull request description."
  --model "$MODEL"
  --system-prompt-file "$here/system-prompt.md"
  --output-format json
  --max-turns 1
  --no-session-persistence
  --setting-sources user
  --strict-mcp-config
  --disable-slash-commands
  --tools ""
)
if [ -n "${EFFORT:-}" ]; then
  args+=(--effort "$EFFORT")
fi

# Environment allowlist: only these job variables are passed through, when set.
environment=(
  PATH="$PATH"
  HOME="$work/home"
  TMPDIR="$work/tmp"
  CLAUDE_CODE_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN"
  CLAUDE_CONFIG_DIR="$work/config"
  CLAUDE_CODE_DISABLE_CLAUDE_MDS=1
  DISABLE_AUTOUPDATER=1
  DISABLE_UPDATES=1
  DISABLE_TELEMETRY=1
  DISABLE_ERROR_REPORTING=1
)
for name in LANG LC_ALL TZ HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy \
  SSL_CERT_FILE SSL_CERT_DIR NODE_EXTRA_CA_CERTS; do
  if [ -n "${!name:-}" ]; then
    environment+=("$name=${!name}")
  fi
done

status=0
(
  cd "$work/cwd"
  exec env -i "${environment[@]}" claude "${args[@]}"
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
