---
title: Action — check-report-inputs
---

# Action — check-report-inputs

Checks the report settings shared by the perf and SEO workflows before any work
starts, and fails with an `::error::` that names the input.
[`perf-sitespeed`](../workflows/perf-sitespeed.md),
[`perf-lighthouse`](../workflows/perf-lighthouse.md),
[`perf-unlighthouse`](../workflows/perf-unlighthouse.md) and
[`seo-crawl`](../workflows/seo-crawl.md) run it as their first step. It needs bash
only, so it runs inside a job container too.

## Usage

```yaml
steps:
  - uses: KevinDeBenedetti/github-workflows/.github/actions/check-report-inputs@main
    with:
      artifact-retention-days: ${{ inputs.artifact-retention-days }}
      upload-artifact: ${{ inputs.upload-artifact }}
```

## Inputs

| Input                     | Default    | Rule                        |
| ------------------------- | ---------- | --------------------------- |
| `artifact-retention-days` | (required) | A whole number from 1 to 90 |
| `upload-artifact`         | (required) | `true` or `false`           |

## Notes

- The script is `check-report-inputs.sh`; its tests are in `tests/check-report-inputs.bats`.
