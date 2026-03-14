# Action — actionlint

Validates GitHub Actions workflow files with [actionlint](https://github.com/rhysd/actionlint).

## Usage

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: KevinDeBenedetti/github-workflows/.github/actions/actionlint@main
    with:
      paths: .github/workflows/
```

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `paths` | string | `.github/workflows/` | Space-separated list of workflow files or directories to validate |
| `flags` | string | `''` | Extra flags passed to actionlint (e.g. `-ignore 'SC2086'`) |

## Steps

1. Download and install `actionlint` `1.7.11` into `$RUNNER_TEMP/actionlint`
2. Collect all `.yml` / `.yaml` files from the given paths
3. Run `actionlint [flags] <files>`

## Notes

- When `paths` points to a directory, all `.yml` and `.yaml` files within it are collected recursively.
- Use `flags: '-ignore SC2086'` to suppress specific ShellCheck rules that actionlint embeds.
- actionlint is downloaded fresh each run; no system-wide install is required.
