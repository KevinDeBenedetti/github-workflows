# Copilot instructions

## Repository overview

`KevinDeBenedetti/github-workflows` is a library of reusable GitHub Actions workflows
and composite actions for Node.js, Python, and shell projects. Every workflow is
triggered via `workflow_call` — callers stay minimal and CI steps run consistently
across repos. The repo also ships ready-to-copy caller examples and per-workflow docs.

## Prerequisites

- `gh` — GitHub CLI (used to interact with the repo and Actions)
- `actionlint` — validates GitHub Actions workflow YAML (used in internal CI)

## Repository layout

```
.github/
  actions/    # Composite actions (setup-node, setup-python, shellcheck,
              #   bats, detect-changes, actionlint, kubeconform)
  workflows/  # Reusable workflows (ci-node, ci-python, ci-shell,
              #   deploy-docker, deploy-pages, deploy-vercel, release, security)
              # Internal CI: ci.yml, test-ci-shell.yml, test-security.yml
examples/     # Ready-to-copy caller workflow files
docs/
  workflows/  # Per-workflow reference (ci-node.md, ci-python.md, …)
  getting-started.md
```

## Reusable workflows

All workflows live under `.github/workflows/` and are called with:

```yaml
uses: KevinDeBenedetti/github-workflows/.github/workflows/<name>.yml@main
secrets: inherit
```

| Workflow            | Key inputs (with defaults)                                                   |
| ------------------- | ---------------------------------------------------------------------------- |
| `ci-node.yml`       | `node-version` (20), `package-manager` (auto), `working-directory` (.), `run-lint/typecheck/test/build` (true), `upload-build` (false), `framework` (auto) |
| `ci-python.yml`     | `python-version` (3.12), `working-directory` (.), `run-lint/format/test` (true), `run-typecheck` (false), `run-coverage` (false), `coverage-fail-under` (80) |
| `ci-shell.yml`      | `run-shellcheck` (true), `shellcheck-severity` (warning), `run-actionlint` (true), `run-bats` (true) |
| `deploy-docker.yml` | `image-name` (repo name), `context` (.), `platforms` (linux/amd64,linux/arm64), `push` (true), `tag-latest` (false) |
| `deploy-pages.yml`  | `working-directory` (.), `node-version` (20), `output-directory` (dist)     |
| `deploy-vercel.yml` | `environment` (preview), `working-directory` (.), `node-version` (20); secrets: `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID` |
| `release.yml`       | `release-type` (""), `config-file` (release-please-config.json), `git-user-name` (github-actions[bot]), `git-user-email` (github-actions[bot]@…); outputs: `released`, `tag` |
| `security.yml`      | `run-node-audit` (true), `run-python-audit` (false), `run-secret-scan` (true), `run-codeql` (true), `codeql-languages` (["javascript","typescript"]) |
| `dependabot-automerge.yml` | `merge-method` (squash), `major-label` (major-update); secret: `PAT_TOKEN` (required — personal account token) |
| `check-bot-commits.yml` | `allowed-bots` ([]), `fail-on-bot-commits` (true); guards PRs against bot-authored commits |
| `renovate.yml`          | `configuration-file` (''); secret: `PAT_TOKEN` (required); opens all dependency PRs as personal user |

## Composite actions

Actions live under `.github/actions/` and are referenced with:

```yaml
uses: KevinDeBenedetti/github-workflows/.github/actions/<name>@main
```

| Action           | Key inputs (with defaults)                                              |
| ---------------- | ----------------------------------------------------------------------- |
| `setup-node`     | `node-version` (20), `working-directory` (.), `package-manager` (auto) |
| `setup-python`   | `python-version` (3.12), `working-directory` (.)                        |
| `shellcheck`     | `severity` (warning), `exclude-paths` (*/test_helper/*)                |
| `bats`           | `tests-dir` (tests/)                                                    |
| `detect-changes` | `apps-directory` (apps); outputs JSON matrix of changed subdirectories  |
| `actionlint`     | `paths` (.github/workflows/), `flags` ("")                             |
| `kubeconform`    | `paths` (kubernetes/), `exclude` ("")                                   |

## Examples

`examples/` contains ready-to-copy caller files:

- `ci-cd.pages.yml` — Node.js CI → GitHub Pages deploy → release-please
- `ci-cd.vercel.yml` — Node.js CI → Vercel preview/production → release-please
- `next.yml` / `nuxt.yml` / `vue-react.yml` — framework-specific CI
- `fastapi.yml` — Python FastAPI CI
- `monorepo.yml` — matrix CI driven by `detect-changes`

## Internal CI

`.github/workflows/ci.yml` runs `actionlint` on all workflow files in
`.github/workflows/` on every push and PR to `main`.

## Key conventions

- All reusable workflows use `workflow_call` only; no direct triggers.
- Reference workflows and actions at `@main`; pin to a commit SHA in production callers.
- `release.yml` automatically moves a `v<major>` alias tag after each release.
- `deploy-docker.yml` pushes to `ghcr.io` (GHCR) and defaults to multi-platform builds.
- `ci-node.yml` auto-detects the package manager from the lockfile (`pnpm-lock.yaml` → pnpm, `bun.lockb` → bun).
- `ci-python.yml` uses `uv` for dependency management and `ruff` for lint/format.
- `security.yml` combines Gitleaks secret scanning, CodeQL SAST, and optional audit steps.
- Docs for each workflow are in `docs/workflows/<workflow-name>.md`.
