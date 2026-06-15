# CI — Shell

Runs **ShellCheck → actionlint → Bats → Docker** for shell script projects.
Each stage is independently toggleable.

## Usage

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-shell.yml@main
    with:
      run-shellcheck: true
      run-actionlint: true
      run-bats: true
      run-link-check: true
      link-check-paths: 'docs/**/*.md'
      run-docker: false
```

## Inputs

| Input                      | Type    | Default                        | Description                                                                  |
| -------------------------- | ------- | ------------------------------ | ---------------------------------------------------------------------------- |
| `run-shellcheck`           | boolean | `true`                         | Run ShellCheck on all `.sh` files                                            |
| `shellcheck-severity`      | string  | `warning`                      | Minimum severity: `error` \| `warning` \| `info` \| `style`                  |
| `shellcheck-exclude-paths` | string  | `*/test_helper/*`              | Glob passed to `find -not -path` to exclude from analysis                    |
| `run-actionlint`           | boolean | `true`                         | Run actionlint on GitHub Actions workflow files                              |
| `actionlint-paths`         | string  | `.github/workflows/`           | Space-separated paths to validate                                            |
| `actionlint-flags`         | string  | `''`                           | Extra flags passed to actionlint                                             |
| `run-bats`                 | boolean | `true`                         | Run Bats unit tests                                                          |
| `bats-tests-dir`           | string  | `tests/`                       | Directory (or file) containing `.bats` test files                            |
| `bats-submodules`          | boolean | `true`                         | Checkout git submodules required by Bats helpers                             |
| `run-docker`               | boolean | `false`                        | Run Docker integration tests                                                 |
| `docker-file`              | string  | `tests/docker/Dockerfile.test` | Path to the test Dockerfile                                                  |
| `docker-targets`           | string  | `'[]'`                         | JSON array of `--target` names to build (e.g. `'["test-bats","test-init"]'`) |
| `run-link-check`           | boolean | `false`                        | Check markdown files for broken relative links (offline, no HTTP requests)   |
| `link-check-paths`         | string  | `docs/**/*.md`                 | Space-separated glob patterns of markdown files to check                     |
| `run-docs-link-check`      | boolean | `false`                        | Check that no relative links in `docs/` escape the `docs/` directory         |
| `runner`                   | string  | `'"ubuntu-latest"'`            | Runner labels as JSON — e.g. `'"ubuntu-latest"'` or `'["self-hosted","linux","k3s","kaniko"]'` |

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
| `link-check`    | `run-link-check: true`                            |
| `docs-link-check` | `run-docs-link-check: true`                     |

## Notes

- Docker targets run in parallel via a matrix strategy with `fail-fast: false`.
- The `bats-submodules` flag applies to both the `bats` and `docker-test` jobs.
- ShellCheck and actionlint use their own composite actions: [`shellcheck`](https://github.com/KevinDeBenedetti/github-workflows/tree/main/.github/actions/shellcheck), [`actionlint`](https://github.com/KevinDeBenedetti/github-workflows/tree/main/.github/actions/actionlint). actionlint covers YAML syntax, expression type checking, and action input validation — no separate yamllint needed.
- `link-check` runs [lychee](https://github.com/lycheeverse/lychee) in offline mode — no external HTTP requests are made.
