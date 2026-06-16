# TODO

## 🔴 En cours

## 🟡 À faire

## 🟢 Idées / backlog

## 🤖 Claude — recommandations

- [ ] CHORE: gate cd-docs.yml dispatch on docs verification passing — it currently fires `docs-updated` to the central site without running check-vitepress-md/check-docs-links first, so a broken doc can still trigger a failing site rebuild


## ✅ Fait

- [x] 2026-06-17 — FEAT: verify docs workflows — wired the orphaned `check-vitepress-md` action into CI via a new `run-vitepress-check` input/job in `ci-shell.yml`, and enabled docs verification (`run-vitepress-check` + `run-docs-link-check`) in `test-workflows.yml` so this repo verifies its own `docs/` before the central docs site rebuilds; documented in `ci-shell.md`
- [x] 2026-06-17 — FEAT: also notify on release PR updates, not only creation — added a `find-prs` step that prefers release-please's `prs` output but falls back to querying open `autorelease: pending` PRs, so untouched/existing release PRs still get a first-time notification (marker guard prevents duplicates)
- [x] 2026-06-17 — CHORE: guard actionlint against the create-github-app-token false positive — pinned actionlint stays at 1.7.11 (1.7.12 regressed), added `-ignore create-github-app-token` flag in test-workflows.yml + documenting comments
- [x] 2026-06-16 — FIX(URGENT): notify on release PR created via GitHub App — release-please opens the PR as the App (not you), so add a reliable @mention comment (plus the existing review request) on the release PR
