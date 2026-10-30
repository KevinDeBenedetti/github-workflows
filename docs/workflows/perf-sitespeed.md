---
title: Perf — sitespeed.io
---

# Perf — sitespeed.io

Core Web Vitals monitoring with [sitespeed.io](https://www.sitespeed.io/) (real
Chrome, official Docker image). The job **fails when the performance budget is
exceeded**, so GitHub's failure email is the alert. Results are kept as
artifacts and, optionally, appended to a CSV on a history branch.

## Usage

```yaml
on:
  schedule:
    - cron: "17 5 * * *"
  workflow_dispatch:

jobs:
  sitespeed:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/perf-sitespeed.yml@main
    permissions:
      contents: write # history job pushes to the history branch
    with:
      device: both
```

The caller needs two files:

```text
perf/urls.txt     # one URL per line
perf/budget.json  # {"budget": {"googleWebVitals": {"largestContentfulPaint": 2500,
                  #   "cumulativeLayoutShift": 0.1, "totalBlockingTime": 300}}}
```

## Inputs

| Input             | Type    | Default                                    | Description                                                         |
| ----------------- | ------- | ------------------------------------------ | ------------------------------------------------------------------- |
| `urls-file`       | string  | `perf/urls.txt`                            | URLs to test, one per line, in the calling repo                     |
| `budget-file`     | string  | `perf/budget.json`                         | sitespeed.io budget JSON in the calling repo                        |
| `iterations`      | number  | `5`                                        | Runs per URL (metrics are the median)                               |
| `device`          | string  | `desktop`                                  | `desktop`, `mobile`, or `both` (matrix of the two)                  |
| `sitespeed-image` | string  | `sitespeedio/sitespeed.io:<tag>@sha256:…`  | Image pinned by tag + digest, bumped by Renovate                    |
| `history-branch`  | string  | `perf-history`                             | Branch receiving `history.csv` (orphan if missing). Empty disables  |
| `runner`          | string  | `'"ubuntu-latest"'`                        | Runner labels as JSON                                               |

## Jobs

1. **`sitespeed`** (one per device) — checkout, validate inputs, run the
   container (`--mobile` for mobile) with the `analysisstorer` plugin, extract
   the median LCP/CLS/TBT, write a step summary, upload
   `sitespeed-result-<device>` (90 days). Extraction and upload use
   `if: always()` so they run even when the budget failed. The medians come
   from the `pages/<host>/<path>/data/browsertime.pageSummary.json` file that
   `analysisstorer` writes for each URL: sitespeed.io writes no JSON without
   that plugin, which is off by default.
2. **`history`** (only if `history-branch` is set) — downloads the artifacts and
   appends `date,url,device,lcp,cls,tbt` rows to `history.csv` on the history
   branch. Has `contents: write`, scoped to this job only. A single job writes
   after the matrix, so `device: both` cannot cause concurrent-push conflicts.

## Notes

- **Do not use a `k3s-*` runner.** Testing from the cluster's own network skews
  LCP and TTFB; the default GitHub-hosted runner is the right vantage point.
- The caller's `permissions:` cap the called workflow. Grant `contents: write`
  on the calling job when the history is enabled; with `history-branch: ''`
  `contents: read` is enough.
- The budget file must wrap the thresholds in a top-level `"budget"` key.
- Start with loose thresholds and tighten them after a week of data.
- No dashboard: alerting is the failure email, history is the CSV + artifacts.

## Run locally

```bash
docker run --rm --shm-size=1g -v "$(pwd)/sitespeed-result:/sitespeed.io" \
  sitespeedio/sitespeed.io:<tag> https://example.com/ -n 5 -b chrome \
  --budget.configPath budget.json --plugins.add analysisstorer
```
