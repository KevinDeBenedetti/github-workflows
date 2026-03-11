# CI — Shell

Runs **ShellCheck → yamllint → Bats → Docker** for shell script projects.
Each stage is independently toggleable.

## Usage

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-shell.yml@main
    with:
      run-shellcheck: true
      run-yamllint: true
      run-bats: true
      run-docker: false
```

## Inputs

| Input                      | Type    | Default                        | Description                                                                  |
| -------------------------- | ------- | ------------------------------ | ---------------------------------------------------------------------------- |
| `run-shellcheck`           | boolean | `true`                         | Run ShellCheck on all `.sh` files                                            |
| `shellcheck-severity`      | string  | `warning`                      | Minimum severity: `error` \| `warning` \| `info` \| `style`                  |
| `shellcheck-exclude-paths` | string  | `*/test_helper/*`              | Glob passed to `find -not -path` to exclude from analysis                    |
| `run-yamllint`             | boolean | `true`                         | Run yamllint on YAML files                                                   |
| `yamllint-paths`           | string  | `.github/workflows/`           | Space-separated paths to validate                                            |
| `run-bats`                 | boolean | `true`                         | Run Bats unit tests                                                          |
| `bats-tests-dir`           | string  | `tests/`                       | Directory (or file) containing `.bats` test files                            |
| `bats-submodules`          | boolean | `true`                         | Checkout git submodules required by Bats helpers                             |
| `run-docker`               | boolean | `false`                        | Run Docker integration tests                                                 |
| `docker-file`              | string  | `tests/docker/Dockerfile.test` | Path to the test Dockerfile                                                  |
| `docker-targets`           | string  | `'[]'`                         | JSON array of `--target` names to build (e.g. `'["test-bats","test-init"]'`) |

## Jobs

| Job             | Condition                                         |
| --------------- | ------------------------------------------------- |
| `shellcheck`    | `run-shellcheck: true`                            |
| `validate-yaml` | `run-yamllint: true`                              |
| `bats`          | `run-bats: true`                                  |
| `docker-test`   | `run-docker: true` (matrix over `docker-targets`) |

## Notes

- Docker targets run in parallel via a matrix strategy with `fail-fast: false`.
- The `bats-submodules` flag applies to both the `bats` and `docker-test` jobs.
- ShellCheck and yamllint use their own composite actions: [`shellcheck`](../.github/actions/shellcheck/action.yml), [`yamllint`](../.github/actions/yamllint/action.yml).
