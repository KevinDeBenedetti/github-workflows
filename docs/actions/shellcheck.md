# Action — shellcheck

Runs [ShellCheck](https://www.shellcheck.net/) on all `.sh` files in the repository.

## Usage

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: KevinDeBenedetti/github-workflows/.github/actions/shellcheck@main
    with:
      severity: warning
```

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `severity` | string | `warning` | Minimum severity level: `error` \| `warning` \| `info` \| `style` |
| `exclude-paths` | string | `*/test_helper/*` | Glob passed to `find -not -path` to exclude from analysis |

## Notes

- Finds all `*.sh` files recursively under the current directory (excluding `exclude-paths`).
- Reports issues in GCC format for clean integration with GitHub annotations.
- Requires ShellCheck to be installed on the runner (available on all `ubuntu-*` runners).
