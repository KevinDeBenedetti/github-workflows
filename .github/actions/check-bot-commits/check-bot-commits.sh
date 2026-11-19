#!/usr/bin/env bash
# Fail a pull request that brings commits authored by a bot account, unless
# the bot is allow-listed.
#
# A commit is a bot's when any of these holds:
#   - the GitHub account it is linked to has the type Bot;
#   - that account's login ends with [bot];
#   - its author e-mail is a bot's no-reply address (<id>+<name>[bot]@users.noreply.github.com);
#   - it is linked to no account and its author name ends with [bot].
# ALLOWED_BOTS lists account logins: a bot commit passes only when it is
# linked to one of them. The author name and e-mail of a commit are whatever
# its author wrote, so they can flag a commit as a bot's, never allow one.
#
# Fails closed: an API error, or a pull request with more commits than GitHub
# lists (250 at most), fails the step whatever FAIL_ON_BOT_COMMITS says.
#
# Talks to the REST API with curl, the token in a header file, never on a
# command line: runner images outside GitHub's often ship no GitHub CLI.
#
# Env: ALLOWED_BOTS          JSON array of account logins (default [])
#      FAIL_ON_BOT_COMMITS   true: fail on a bot commit; false: warn (default true)
#      PR_NUMBER             the pull request; empty: not a pull request, nothing to check
#      PR_COMMITS            the pull request's commit count, from the event (optional)
#      GITHUB_TOKEN          pull-requests read (required)
#      GITHUB_REPOSITORY     owner/name (required)
#      GITHUB_API_URL        REST API root, set by the runner (default: https://api.github.com)
# Outputs (GITHUB_OUTPUT): checked (commits checked) and blocked (bot commits
# not allowed). The job summary lists every commit author with its verdict.
set -euo pipefail

ALLOWED_BOTS="${ALLOWED_BOTS:-[]}"
FAIL_ON_BOT_COMMITS="${FAIL_ON_BOT_COMMITS:-true}"
PR_NUMBER="${PR_NUMBER:-}"
PR_COMMITS="${PR_COMMITS:-}"
# GitHub lists 250 commits of a pull request at most, 100 a page.
MAX_PAGES=3

fail() {
  echo "::error::$*" >&2
  exit 1
}

case "$FAIL_ON_BOT_COMMITS" in
  true | false) ;;
  *) fail "FAIL_ON_BOT_COMMITS must be true or false, not '$FAIL_ON_BOT_COMMITS'" ;;
esac
jq -e 'type == "array" and all(type == "string")' <<< "$ALLOWED_BOTS" > /dev/null 2>&1 ||
  fail "ALLOWED_BOTS must be a JSON array of logins, such as '[\"dependabot[bot]\"]', not '$ALLOWED_BOTS'"
[[ -z "$PR_COMMITS" || "$PR_COMMITS" =~ ^[0-9]{1,9}$ ]] ||
  fail "PR_COMMITS must be a whole number, not '$PR_COMMITS'"

if [ -z "$PR_NUMBER" ]; then
  echo "::notice::Not a pull request: no commit to check."
  exit 0
fi
[[ "$PR_NUMBER" =~ ^[1-9][0-9]{0,9}$ ]] || fail "PR_NUMBER must be a pull request number, not '$PR_NUMBER'"
: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
[[ "$GITHUB_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
  fail "GITHUB_REPOSITORY must be owner/name, not '$GITHUB_REPOSITORY'"
# The token travels only over TLS, to the API root the runner names.
api_url="${GITHUB_API_URL:-https://api.github.com}"
case "$api_url" in
  https://[!/]*) ;;
  *) fail "GITHUB_API_URL must be an https:// URL, not '$api_url'" ;;
esac
api_root="${api_url%/}/repos/${GITHUB_REPOSITORY}"

work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/check-bot-commits.XXXXXX")"
trap 'rm -rf "$work"' EXIT
(umask 077 && printf 'Authorization: Bearer %s\n' "$GITHUB_TOKEN" > "$work/auth-header")

# api RESPONSE [curl args...]: prints the HTTP status; the body, error answers
# included, lands in RESPONSE.
api() {
  local response="$1"
  shift
  curl -sS --retry 3 --retry-delay 2 --max-time 60 \
    -H @"$work/auth-header" \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    -o "$response" -w '%{http_code}' "$@"
}
message() { jq -r '.message? // empty' "$1" 2> /dev/null || true; }

# One commit per line: sha, login, account type, author name, author e-mail,
# separated by the unit separator (\x1f). A tab would not do: bash folds runs
# of whitespace separators, so an empty login would shift the fields. The
# author's fields are free text: control characters, the separator included,
# become spaces.
: > "$work/commits.txt"
page=1
while ((page <= MAX_PAGES)); do
  status="$(api "$work/page.json" "${api_root}/pulls/${PR_NUMBER}/commits?per_page=100&page=${page}")" ||
    fail "could not reach GitHub to list the commits of pull request #${PR_NUMBER}: refusing to pass unchecked"
  [ "$status" = 200 ] ||
    fail "GitHub answered $status listing the commits of pull request #${PR_NUMBER}: $(message "$work/page.json") — refusing to pass unchecked (does the job grant pull-requests: read?)"
  jq -r '.[] | [.sha, (.author.login // ""), (.author.type // ""), (.commit.author.name // ""), (.commit.author.email // "")]
    | map(gsub("[\u0000-\u001f\u007f]"; " ")) | join("\u001f")' "$work/page.json" >> "$work/commits.txt"
  (($(jq length "$work/page.json") == 100)) || break
  page=$((page + 1))
done
checked="$(wc -l < "$work/commits.txt" | tr -d ' ')"

if [ -n "$PR_COMMITS" ] && ((10#$PR_COMMITS > checked)); then
  fail "pull request #${PR_NUMBER} has $((10#$PR_COMMITS)) commits and GitHub lists $checked of them (250 at most): refusing to pass unchecked — split the pull request, or squash its commits"
fi

# md TEXT: TEXT as plain text in a Markdown table cell — no link, HTML, code
# span or emphasis an author could write into the summary.
md() {
  local s="$1"
  s="${s//"\\"/'\\'}"
  s="${s//"|"/'\|'}"
  s="${s//'`'/'\`'}"
  s="${s//"*"/'\*'}"
  s="${s//"_"/'\_'}"
  s="${s//"["/'\['}"
  s="${s//"]"/'\]'}"
  s="${s//"<"/'&lt;'}"
  s="${s//">"/'&gt;'}"
  printf '%s' "$s"
}

blocked=0
rows=""
bot_email_re='^[0-9]+\+[^@]*\[bot\]@users\.noreply\.github\.com$'
while IFS=$'\x1f' read -r sha login type name email; do
  is_bot=false
  if [ "$type" = Bot ] || [[ "$login" == *"[bot]" ]] || [[ "$email" =~ $bot_email_re ]] ||
    { [ -z "$login" ] && [[ "$name" == *"[bot]" ]]; }; then
    is_bot=true
  fi
  if [ -n "$login" ]; then
    who="$login"
  else
    who="$name <$email> (no GitHub account)"
  fi
  if [ "$is_bot" = false ]; then
    verdict="Human"
    echo "  👤 ${sha:0:7} $who"
  elif [ -n "$login" ] && jq -e --arg login "$login" 'index($login) != null' <<< "$ALLOWED_BOTS" > /dev/null; then
    verdict="Bot (allowed)"
    echo "  ✅ ${sha:0:7} allowed bot: $who"
  else
    verdict="Bot — blocked"
    blocked=$((blocked + 1))
    echo "  ❌ ${sha:0:7} bot commit: $who <$email>"
  fi
  rows+="| ${sha:0:7} | $(md "$who") | $verdict |"$'\n'
done < "$work/commits.txt"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  printf 'checked=%s\nblocked=%s\n' "$checked" "$blocked" >> "$GITHUB_OUTPUT"
fi
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## 🤖 Bot commit check"
    echo
    if ((checked == 0)); then
      echo "No commit in this pull request."
    else
      echo "| Commit | Author | Verdict |"
      echo "| ------ | ------ | ------- |"
      printf '%s' "$rows"
    fi
    echo
    if ((blocked > 0)); then
      echo "> ❌ **$blocked bot commit(s).** Rebase and squash them, or add the bot to \`allowed-bots\`."
    else
      echo "> ✅ **No bot commit outside \`allowed-bots\`.**"
    fi
  } >> "$GITHUB_STEP_SUMMARY"
fi

if ((blocked == 0)); then
  echo "✅ $checked commit(s) checked: no bot commit outside allowed-bots."
  exit 0
fi
if [ "$FAIL_ON_BOT_COMMITS" = true ]; then
  fail "$blocked bot commit(s) in pull request #${PR_NUMBER}: rebase and squash them, or add the bot to allowed-bots"
fi
echo "::warning::$blocked bot commit(s) in pull request #${PR_NUMBER}, allowed because fail-on-bot-commits is false"
