# Action — shellcheck

Runs [ShellCheck](https://www.shellcheck.net/) on all `.sh` files in the repository, and on the extensionless scripts `extra-paths` names.

## Usage

```yaml
steps:
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

  - uses: KevinDeBenedetti/github-workflows/.github/actions/shellcheck@main
    with:
      severity: warning
```

## Inputs

| Input           | Type   | Default           | Description                                                                                |
| --------------- | ------ | ----------------- | ------------------------------------------------------------------------------------------ |
| `severity`      | string | `warning`         | Minimum severity level: `error` \| `warning` \| `info` \| `style`                          |
| `exclude-paths` | string | `*/test_helper/*` | One glob passed to `find -not -path` to exclude from analysis                              |
| `extra-paths`   | string | `''`              | Space-separated globs (`find -path`, from the repository root) checked whatever their name |
| `default-shell` | string | `bash`            | Dialect for scripts with neither a supported shebang nor a `# shellcheck shell=` directive |

## Notes

- Finds all `*.sh` files recursively under the current directory (excluding `exclude-paths`, and never descending into `.git`, `node_modules` or `.venv`).
- Each script is checked as the shell its shebang (or `# shellcheck shell=` directive) declares, so `#!/bin/sh` scripts get POSIX checks; only undeclared scripts, and scripts whose shebang names a shell ShellCheck does not support (`zsh`, `fish`…), fall back to `default-shell`.
- A file only `extra-paths` matches (`scripts/*/*` for commands without an extension) is checked when its shebang or a `# shellcheck shell=` directive declares a supported shell. The others, a Python tool or a README among the scripts, are skipped and listed in a notice instead of failing the step. `exclude-paths` applies to them too.
- Reports issues in GCC format for clean integration with GitHub annotations.
- An unknown `severity` or `default-shell` fails the step. The rules are at the top of `shellcheck.sh`, next to `action.yml`.
- Installs a pinned ShellCheck release (x86_64 or aarch64) with [`install-tool`](install-tool.md), which needs `python3` on the runner.
