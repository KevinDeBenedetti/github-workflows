#!/usr/bin/env bats
# Tests for .github/actions/ai-commit-msg/ai-commit-msg.sh
#
# The generation path is exercised with a FAKE `claude` binary (via
# AI_COMMIT_CLAUDE_BIN) so the suite is deterministic and needs no network — it
# mirrors the manual verification the hook was developed against.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/ai-commit-msg/ai-commit-msg.sh"

  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  cd "$REPO" || return 1
  git init -q
  git config user.email t@example.com
  git config user.name test

  MSG="$REPO/COMMIT_EDITMSG"

  # Fake `claude` that echoes a canned Conventional Commits message and ignores
  # all flags (-p, --model, --strict-mcp-config, …).
  FAKE_CLAUDE="$BATS_TEST_TMPDIR/claude"
  cat > "$FAKE_CLAUDE" <<'EOF'
#!/bin/sh
echo "feat: add greeting"
echo ""
echo "- add hello world output"
EOF
  chmod +x "$FAKE_CLAUDE"
}

# Non-comment, non-blank lines currently in the message file.
content_lines() { grep -cvE '^[[:space:]]*(#|$)' "$MSG"; }

stage_change() {
  echo "hello" > file.txt
  git add file.txt
}

@test "disabled via AI_COMMIT_NO_AI is a no-op" {
  stage_change
  : > "$MSG"
  AI_COMMIT_NO_AI=1 AI_COMMIT_CLAUDE_BIN="$FAKE_CLAUDE" bash "$SCRIPT" "$MSG" "" ""
  [ "$(content_lines)" -eq 0 ]
}

@test "an explicit -m source is a no-op" {
  stage_change
  : > "$MSG"
  AI_COMMIT_CLAUDE_BIN="$FAKE_CLAUDE" bash "$SCRIPT" "$MSG" "message" ""
  [ "$(content_lines)" -eq 0 ]
}

@test "a merge source is a no-op" {
  stage_change
  : > "$MSG"
  AI_COMMIT_CLAUDE_BIN="$FAKE_CLAUDE" bash "$SCRIPT" "$MSG" "merge" ""
  [ "$(content_lines)" -eq 0 ]
}

@test "an existing message is preserved" {
  stage_change
  printf 'fix: keep me\n' > "$MSG"
  AI_COMMIT_CLAUDE_BIN="$FAKE_CLAUDE" bash "$SCRIPT" "$MSG" "" ""
  run cat "$MSG"
  [ "$output" = "fix: keep me" ]
}

@test "nothing staged is a no-op" {
  : > "$MSG"
  AI_COMMIT_CLAUDE_BIN="$FAKE_CLAUDE" bash "$SCRIPT" "$MSG" "" ""
  [ "$(content_lines)" -eq 0 ]
}

@test "an unresolvable claude binary is a no-op" {
  stage_change
  : > "$MSG"
  AI_COMMIT_CLAUDE_BIN="$BATS_TEST_TMPDIR/does-not-exist" bash "$SCRIPT" "$MSG" "" ""
  [ "$(content_lines)" -eq 0 ]
}

@test "resolve_claude honors AI_COMMIT_CLAUDE_BIN and prepends the generated message" {
  stage_change
  : > "$MSG"
  # Strip PATH down so a bare `claude` cannot be found — only the override resolves.
  PATH="/usr/bin:/bin" AI_COMMIT_CLAUDE_BIN="$FAKE_CLAUDE" bash "$SCRIPT" "$MSG" "" ""
  run head -n 1 "$MSG"
  [ "$output" = "feat: add greeting" ]
  grep -q "add hello world output" "$MSG"
}

@test "code fences are stripped from the model output" {
  stage_change
  : > "$MSG"
  cat > "$FAKE_CLAUDE" <<'EOF'
#!/bin/sh
echo '```'
echo "chore: tidy"
echo '```'
EOF
  chmod +x "$FAKE_CLAUDE"
  AI_COMMIT_CLAUDE_BIN="$FAKE_CLAUDE" bash "$SCRIPT" "$MSG" "" ""
  run head -n 1 "$MSG"
  [ "$output" = "chore: tidy" ]
  ! grep -q '```' "$MSG"
}

@test "the existing comment block is kept below the generated message" {
  stage_change
  printf '# Please enter the commit message\n# lines starting with # are ignored\n' > "$MSG"
  AI_COMMIT_CLAUDE_BIN="$FAKE_CLAUDE" bash "$SCRIPT" "$MSG" "" ""
  run head -n 1 "$MSG"
  [ "$output" = "feat: add greeting" ]
  grep -q "Please enter the commit message" "$MSG"
}
