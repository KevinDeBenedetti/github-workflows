# TODO

## 🔴 En cours

## 🟡 À faire

## 🟢 Idées / backlog

## 🤖 Claude — recommandations

- [ ] FEAT: make check-docs-links / check-vitepress-md honor a docs-directory input — the new cd-docs `verify` job (and the actions) scan a hardcoded `docs/`, so a caller using a non-default `docs-directory` would verify the wrong folder
- [ ] TEST: add a Bats suite for purge-todo-done.sh covering the staged/unstaged/merge/empty-Fait cases (as done manually) — same regression-guard rationale as the ai-commit-msg suite
- [ ] TEST: cover resolve_claude's PATH/common-location fallback directly — the new suite only exercises the AI_COMMIT_CLAUDE_BIN override (a real `claude` at /opt/homebrew/bin shadows the fallback list, so the probe order is untested)

## ✅ Fait
