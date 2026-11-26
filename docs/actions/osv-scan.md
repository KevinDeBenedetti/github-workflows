---
title: Action — osv-scan
---

# Action — osv-scan

Audits the dependencies of every lockfile of a directory against the
[OSV](https://osv.dev) advisory database with
[OSV-Scanner](https://github.com/google/osv-scanner), whatever the ecosystem: npm,
pnpm, bun, PyPI, Go, Cargo and the others it reads. It is the `osv-scan` job of
[`security.yml`](../workflows/security.md).

## Usage

```yaml
steps:
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
    with:
      persist-credentials: false

  - uses: KevinDeBenedetti/github-workflows/.github/actions/osv-scan@main
```

## Inputs

| Input  | Default | Description                    |
| ------ | ------- | ------------------------------ |
| `path` | `.`     | Directory to scan, recursively |

## Steps

1. Install the pinned `osv-scanner` with [`install-tool`](install-tool.md)
2. `osv-scanner scan source --recursive <path>`

## Notes

- A known vulnerability fails the step, with OSV-Scanner's table in the log.
- A directory without any lockfile or manifest passes with a notice (OSV-Scanner's exit code 128).
- Any other failure (the OSV API does not answer, an invalid `osv-scanner.toml`) fails the step with OSV-Scanner's exit code.
- Nothing is installed: the lockfiles are read as they are, so no dependency's lifecycle script runs.
- Ignore an advisory with an `[[IgnoredVulns]]` entry in an `osv-scanner.toml` next to the lockfile.
- The script is `osv-scan.sh`; its tests are in `tests/osv-scan.bats`.
