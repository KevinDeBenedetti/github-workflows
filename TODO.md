# TODO

## 🔴 En cours

## 🟡 À faire
- [ ] CHORE: gate cd-docs.yml dispatch on docs verification passing — it currently fires `docs-updated` to the central site without running check-vitepress-md/check-docs-links first, so a broken doc can still trigger a failing site rebuild
- [ ] TEST: add a Bats suite for ai-commit-msg.sh covering the no-op guards + resolve_claude fallback (using a fake `claude` bin, as done manually) — locks in the fail-open behaviour against regressions
- [ ] CHORE: smoke-test the ai-commit-msg generation path against the live Claude API — it couldn't be verified in the dev sandbox (no network to the Anthropic API); confirm a real `git commit` in VS Code pre-fills a message after `prek install -t prepare-commit-msg`

## 🟢 Idées / backlog

## 🤖 Claude — recommandations

## ✅ Fait
