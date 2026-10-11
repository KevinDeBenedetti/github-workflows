# Action — shellcheck

Runs [ShellCheck](https://www.shellcheck.net/) on all `.sh` files in the repository.

## Usage

```yaml
steps:
  - uses: actions/checkout@v7

  - uses: KevinDeBenedetti/github-workflows/.github/actions/shellcheck@main
    with:
      severity: warning
```

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `severity` | string | `warning` | Minimum severity level: `error` \| `warning` \| `info` \| `style` |
| `exclude-paths` | string | `*/test_helper/*` | Glob passed to `find -not -path` to exclude from analysis |
| `default-shell` | string | `bash` | Dialect for scripts with neither a shebang nor a `# shellcheck shell=` directive |

## Notes

- Finds all `*.sh` files recursively under the current directory (excluding `exclude-paths`, and never descending into `.git`, `node_modules` or `.venv`).
- Each script is checked as the shell its shebang (or `# shellcheck shell=` directive) declares, so `#!/bin/sh` scripts get POSIX checks; only undeclared scripts fall back to `default-shell`.
- Reports issues in GCC format for clean integration with GitHub annotations.
- Installs a pinned ShellCheck release (x86_64 or aarch64) — nothing needs to be preinstalled on the runner.
