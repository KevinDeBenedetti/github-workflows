# TODO

## 🔴 En cours

## 🟡 À faire

- [ ] FEAT: also notify on release PR updates, not only creation — currently only fires on `prs_created == 'true'`, so an updated existing release PR sends no notification
- [ ] FEAT: verify docs workflows
- [ ] FEAT: add full tests and clear refactoring for github workflows / actions
- [ ] FEAT: dependencies updates / check for updates in github workflows / actions

## 🟢 Idées / backlog

## 🤖 Claude — recommandations



## ✅ Fait

- [x] 2026-06-17 — CHORE: guard actionlint against the create-github-app-token false positive — pinned actionlint stays at 1.7.11 (1.7.12 regressed), added `-ignore create-github-app-token` flag in test-workflows.yml + documenting comments
- [x] 2026-06-16 — FIX(URGENT): notify on release PR created via GitHub App — release-please opens the PR as the App (not you), so add a reliable @mention comment (plus the existing review request) on the release PR
