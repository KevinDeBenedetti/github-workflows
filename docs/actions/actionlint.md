---
title: Action — actionlint
---

# Action — actionlint

Validates GitHub Actions workflow files with [actionlint](https://github.com/rhysd/actionlint).

## Usage

```yaml
steps:
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

  - uses: KevinDeBenedetti/github-workflows/.github/actions/actionlint@main
    with:
      paths: .github/workflows/
```

## Inputs

| Input   | Type   | Default              | Description                                                                                 |
| ------- | ------ | -------------------- | ------------------------------------------------------------------------------------------- |
| `paths` | string | `.github/workflows/` | Space-separated workflow files, directories and globs to validate                           |
| `flags` | string | `''`                 | Extra flags passed to actionlint, split like a shell command line (e.g. `-ignore 'SC2086'`) |

## Steps

1. Install the pinned `actionlint` (`1.7.11`) into `$RUNNER_TEMP/actionlint` with [`install-tool`](install-tool.md)
2. Collect the `.yml` / `.yaml` files of `paths` and split `flags` (`actionlint.sh`)
3. Run `actionlint [flags] <files>`

## Notes

- When a `paths` entry is a directory, all `.yml` and `.yaml` files within it are collected recursively. A glob (`.github/workflows/ci-*.yml`) is expanded. An entry that matches nothing fails the step, so a typo cannot skip the check.
- `flags` honours shell quoting: `flags: -ignore 'SC2086'` passes one pattern, `-ignore "a b"` one pattern with a space. An unmatched quote fails the step. Before this, quotes reached actionlint as part of the pattern, which then matched nothing.
- Needs `python3` on the runner to split `flags`, as [`install-tool`](install-tool.md) does.
- actionlint is downloaded fresh each run; no system-wide install is required.
- actionlint does not know the `ubuntu-26.04` and `ubuntu-26.04-arm` runner labels yet, and fails a literal `runs-on: ubuntu-26.04` as an unknown label. List them in the repository's `.github/actionlint.yaml`, which actionlint reads by itself, as this repository does:

  ```yaml
  self-hosted-runner:
    labels:
      - ubuntu-26.04
      - ubuntu-26.04-arm
  ```
