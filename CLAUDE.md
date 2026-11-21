# CLAUDE.md

## Verify a change

`CONTRIBUTING.md` (Set up) has the hooks and the commands of the gate. In short:

- `prek run --all-files`: whitespace, YAML/JSON, actionlint, ShellCheck, the docs checks and the consistency of the workflows.
- `bats tests/`: every script's tests (over a minute). A new or changed script ships with its suite.
- zizmor, pedantic persona, after a change to a workflow or an action: the command is in `CONTRIBUTING.md`.

Commits and pull request titles are Conventional Commits: release-please reads them.

## Agent skills

### Issue tracker

GitHub Issues of this repository, through the `gh` CLI. See `.agents/issue-tracker.md`.

### Triage labels

The five default roles (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`), as GitHub labels of the same names. See `.agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at the repo root, created only when a term or decision is settled. See `.agents/domain.md`.
