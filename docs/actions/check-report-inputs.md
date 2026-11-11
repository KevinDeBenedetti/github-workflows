---
title: Action — check-report-inputs
---

# Action — check-report-inputs

Checks the report settings shared by the perf and SEO workflows before any work
starts, and fails with an `::error::` that names the input. No secret is ever
printed. [`perf-sitespeed`](../workflows/perf-sitespeed.md),
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
      s3-endpoint: ${{ inputs.report-s3-endpoint }}
      s3-bucket: ${{ inputs.report-s3-bucket }}
      s3-prefix: ${{ inputs.report-s3-prefix }}
      s3-access-key-id: ${{ secrets.report-s3-access-key-id }}
      s3-secret-access-key: ${{ secrets.report-s3-secret-access-key }}
```

## Inputs

| Input                     | Default    | Rule                                                                          |
| ------------------------- | ---------- | ----------------------------------------------------------------------------- |
| `artifact-retention-days` | (required) | A whole number from 1 to 90                                                   |
| `upload-artifact`         | (required) | `true` or `false`                                                             |
| `s3-bucket`               | `''`       | Empty: no S3 copy. Otherwise 3 to 63 letters, digits, dots or hyphens         |
| `s3-endpoint`             | `''`       | With a bucket: the `https://` URL of the S3 API host, no path, no credentials |
| `s3-prefix`               | `''`       | Letters, digits and `. _ - /`, with no `.` or `..` segment                    |
| `s3-access-key-id`        | `''`       | Required with a bucket; named in the error, never printed                     |
| `s3-secret-access-key`    | `''`       | Required with a bucket; named in the error, never printed                     |

## Notes

- S3 settings without a bucket only warn: nothing is copied.
- The script is `check-report-inputs.sh`; its tests are in `tests/check-report-inputs.bats`.
