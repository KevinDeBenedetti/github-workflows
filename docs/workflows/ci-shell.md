---
title: CI — Shell
---

# CI — Shell

Runs **ShellCheck → actionlint → Bats → Docker** for shell script projects.
Each stage is independently toggleable.

## Usage

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-shell.yml@v0.56.2 # x-release-please-version
    with:
      run-shellcheck: true
      run-actionlint: true
      run-bats: true
      run-docker: false
```

## Inputs

| Input                      | Type    | Default                        | Description                                                                  |
| -------------------------- | ------- | ------------------------------ | ---------------------------------------------------------------------------- |
| `run-shellcheck`           | boolean | `true`                         | Run ShellCheck on all `.sh` files                                            |
| `shellcheck-severity`      | string  | `warning`                      | Minimum severity: `error` \| `warning` \| `info` \| `style`                  |
| `shellcheck-exclude-paths` | string  | `*/test_helper/*`              | Glob passed to `find -not -path` to exclude from analysis                    |
| `shellcheck-extra-paths`   | string  | `''`                           | Space-separated globs whose files are checked too, whatever their extension  |
| `run-actionlint`           | boolean | `true`                         | Run actionlint on GitHub Actions workflow files                              |
| `actionlint-paths`         | string  | `.github/workflows/`           | Space-separated files, directories and globs; one matching nothing fails     |
| `actionlint-flags`         | string  | `''`                           | Extra flags passed to actionlint, split like a shell command line            |
| `run-bats`                 | boolean | `true`                         | Run Bats unit tests                                                          |
| `bats-tests-dir`           | string  | `tests/`                       | Directory (or file) containing `.bats` test files                            |
| `bats-submodules`          | boolean | `true`                         | Checkout git submodules required by Bats helpers                             |
| `bats-recursive`           | boolean | `false`                        | Also run `.bats` files in sub-directories of `bats-tests-dir`                |
| `run-docker`               | boolean | `false`                        | Run Docker integration tests                                                 |
| `docker-file`              | string  | `tests/docker/Dockerfile.test` | Path to the test Dockerfile                                                  |
| `docker-targets`           | string  | `'[]'`                         | JSON array of `--target` names to build (e.g. `'["test-bats","test-init"]'`) |
| `run-link-check`           | boolean | `false`                        | **Deprecated**, use [`ci-docs`](./ci-docs.md). Check markdown files for broken relative links (offline, no HTTP requests)   |
| `link-check-paths`         | string  | `docs/**/*.md`                 | **Deprecated**, use [`ci-docs`](./ci-docs.md). Space-separated glob patterns of markdown files to check                     |
| `run-docs-link-check`      | boolean | `false`                        | **Deprecated**, use [`ci-docs`](./ci-docs.md). Check that no relative links in `docs/` escape the `docs/` directory         |
| `run-vitepress-check`      | boolean | `false`                        | **Deprecated**, use [`ci-docs`](./ci-docs.md). Check `docs/` markdown for unescaped Vue interpolations that break the VitePress SSR build |
| `run-docs-external-link-check` | boolean | `false`                    | **Deprecated**, use [`ci-docs`](./ci-docs.md). Check the `http(s)` links of the `docs/` markdown files changed by the push or pull request (lychee) |
| `docs-directory`           | string  | `docs`                         | **Deprecated**, use [`ci-docs`](./ci-docs.md). Path to the docs folder checked by `docs-link-check`, `docs-external-link-check` and `vitepress-check` |
| `runner`                   | string  | `'"ubuntu-26.04"'`             | Runner labels as JSON — e.g. `'"ubuntu-26.04"'` or `'"ubicloud-standard-2"'`  |

## Secrets

| Secret  | Required | Description                                                                                       |
| ------- | -------- | ------------------------------------------------------------------------------------------------- |
| `token` | no       | GitHub token or PAT used to checkout private submodules. Falls back to the default `GITHUB_TOKEN`. |

## Jobs

| Job             | Condition                                         |
| --------------- | ------------------------------------------------- |
| `shellcheck`    | `run-shellcheck: true`                            |
| `validate-yaml` | `run-actionlint: true`                            |
| `bats`          | `run-bats: true`                                  |
| `docker-test`   | `run-docker: true` (matrix over `docker-targets`) |
| `link-check`    | `run-link-check: true` (deprecated)               |
| `docs-link-check` | `run-docs-link-check: true` (deprecated)        |
| `docs-external-link-check` | `run-docs-external-link-check: true` (deprecated) |
| `vitepress-check` | `run-vitepress-check: true` (deprecated)        |

## Notes

- Docker targets run in parallel via a matrix strategy with `fail-fast: false`.
- The `bats-submodules` flag applies to both the `bats` and `docker-test` jobs, and so does the `token` secret: a private submodule is checked out with it in both.
- Every job is cut off after 15 minutes (`docker-test`: 30), so a hung check never holds a runner for GitHub's default 6 hours.
- ShellCheck and actionlint use their own composite actions: [`shellcheck`](https://github.com/KevinDeBenedetti/github-workflows/tree/main/.github/actions/shellcheck), [`actionlint`](https://github.com/KevinDeBenedetti/github-workflows/tree/main/.github/actions/actionlint). actionlint covers YAML syntax, expression type checking, and action input validation — no separate yamllint needed.
- The four docs jobs (`link-check`, `docs-link-check`, `docs-external-link-check`, `vitepress-check`) are deprecated: [`ci-docs`](./ci-docs.md) runs the same checks with the same inputs. Here they print a warning and leave in the next breaking release.
