# TODO

## 🔴 En cours

## 🟡 À faire
- [ ] TEST: add a Bats suite for purge-todo-done.sh covering the staged/unstaged/merge/empty-Fait cases (as done manually) — same regression-guard rationale as the ai-commit-msg suite
- [ ] TEST: cover resolve_claude's PATH/common-location fallback directly — the new suite only exercises the AI_COMMIT_CLAUDE_BIN override (a real `claude` at /opt/homebrew/bin shadows the fallback list, so the probe order is untested)


## 🟢 Idées / backlog

## 🤖 Claude — recommandations

- [ ] FEAT: expose a docs-directory input on ci-shell.yml's docs-link-check / vitepress-check jobs — the actions now support it, but ci-shell still always checks `docs/`, so the capability is unreachable from the CI workflow
- [ ] CHORE: if you want Fait purged regardless of client, add a CI workflow that strips TODO.md's Fait section on push — the prepare-commit-msg hook is client-side only, so GitHub-UI commits or contributors without `prek install -t prepare-commit-msg` won't purge

## ✅ Fait
