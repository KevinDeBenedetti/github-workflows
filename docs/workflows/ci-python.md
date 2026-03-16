# CI — Python

Runs **lint → format → typecheck → test** for a Python application.
Uses **uv** for dependency management, **ruff** for lint/format, and **ty** for type checking.

## Usage

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-python.yml@main
    with:
      python-version: '3.12'
      working-directory: '.'
```

## Inputs

| Input                 | Type    | Default                       | Description                                               |
| --------------------- | ------- | ----------------------------- | --------------------------------------------------------- |
| `python-version`      | string  | `'3.12'`                      | Python version                                            |
| `working-directory`   | string  | `'.'`                         | Path to the app root (e.g. `apps/api`)                    |
| `run-lint`            | boolean | `true`                        | Run `ruff check`                                          |
| `run-format`          | boolean | `true`                        | Run `ruff format --check`                                 |
| `run-typecheck`       | boolean | `false`                       | Run `ty check`                                            |
| `run-test`            | boolean | `true`                        | Run pytest                                                |
| `run-coverage`        | boolean | `false`                       | Enable coverage report via `pytest-cov`                   |
| `coverage-fail-under` | number  | `80`                          | Minimum coverage percentage required to pass              |
| `test-command`        | string  | `uv run pytest --tb=short -q` | Custom pytest command (ignored when `run-coverage: true`) |

## Steps

1. Checkout
2. Setup Python + uv (via [`setup-python`](https://github.com/KevinDeBenedetti/github-workflows/tree/main/.github/actions/setup-python))
3. Lint (`ruff check --output-format github`)
4. Format check (`ruff format --check`)
5. Type check (`ty check --output-format github`)
6. Test (`pytest`, with or without `pytest-cov`)

## Notes

- When `run-coverage: true`, the `test-command` input is ignored and coverage flags are applied automatically.
- `coverage-fail-under` only applies when `run-coverage: true`.
