---
title: Perf — sitespeed.io
---

# Perf — sitespeed.io

Core Web Vitals monitoring with [sitespeed.io](https://www.sitespeed.io/) (real
Chrome, official Docker image). The job **fails when the performance budget is
exceeded**, so GitHub's failure email is the alert. By default the metrics are
appended to a CSV on a history branch, and the raw results are kept as
artifacts for a few days, or not uploaded at all.
sitespeed.io runs inside its pinned image as the job's container: the runner
needs no Docker daemon and no Chrome.

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

| Input                     | Type    | Default                                   | Description                                                                      |
| ------------------------- | ------- | ----------------------------------------- | -------------------------------------------------------------------------------- |
| `urls-file`               | string  | `perf/urls.txt`                           | URLs to test, one per line, in the calling repo                                  |
| `budget-file`             | string  | `perf/budget.json`                        | sitespeed.io budget JSON in the calling repo                                     |
| `iterations`              | number  | `5`                                       | Runs per URL (metrics are the median)                                            |
| `device`                  | string  | `desktop`                                 | `desktop`, `mobile`, or `both` (matrix of the two)                               |
| `sitespeed-image`         | string  | `sitespeedio/sitespeed.io:<tag>@sha256:…` | Image the job runs in, pinned by tag + digest, bumped by Renovate                |
| `history-branch`          | string  | `perf-history`                            | Branch receiving `history.csv` (orphan if missing). Empty disables               |
| `artifact-retention-days` | number  | `7`                                       | Days the artifacts are kept, 1 to 90; the repository's retention setting caps it |
| `upload-artifact`         | boolean | `true`                                    | `false` uploads nothing to GitHub: a check that only gates on the budget         |
| `runner`                  | string  | `'"ubuntu-26.04"'`                        | Runner labels as JSON                                                            |

## Jobs

1. **`sitespeed`** (one per device) — runs inside `sitespeed-image` as the job's
   container: checks the report inputs, checks out the caller's files (through the
   REST API: the image has no git), validates the inputs, runs sitespeed.io
   (`--mobile` for mobile) with the `analysisstorer` plugin, extracts the median
   LCP/CLS/TBT, writes a step summary, then uploads `sitespeed-result-<device>`
   (`artifact-retention-days`, 7 days by default).
   Extraction and uploads run even when the budget failed. The medians come from
   the `pages/<host>/<path>/data/browsertime.pageSummary.json` file that
   `analysisstorer` writes for each URL: sitespeed.io writes no JSON without that
   plugin, which is off by default.
2. **`history`** (only if `history-branch` is set) — on the runner itself, appends
   the `date,url,device,lcp,cls,tbt` rows to `history.csv` on the history branch.
   It reads them from the outputs of the `sitespeed` jobs, not from the artifacts,
   so it works with `upload-artifact: false`. Has `contents: write`, scoped to this
   job only. A single job writes after the matrix, so `device: both` cannot cause
   concurrent-push conflicts.

## Artifacts and history

The `sitespeed-result-<device>` artifacts hold the raw results: the HTML report,
the videos, screenshots and HAR files, often tens of megabytes per device and
run. They are kept `artifact-retention-days`, 7 days by default, because the
metrics live elsewhere:

- the `history` job appends the medians to `history.csv` on the history branch;
- the step summary of each run shows the same medians.

Keep the artifacts longer only to look into an old run's videos or HAR files, or
set `upload-artifact: false` and keep none: the history does not need them. With
the history disabled (`history-branch: ''`), the artifacts are the only record of
the metrics.

Artifacts count against the account's GitHub Actions storage for every hour
they exist, a branch does not. The repository's retention setting
(**Settings → Actions → General → Artifact and log retention**) caps the value:
in a repository set to 3 days, the artifacts are kept 3 days and
`actions/upload-artifact` warns that it lowered the value.

::: warning The HAR files are in the artifacts
The HAR files record every request and response of the measured pages, headers
included: cookies, tokens in URLs, whatever a page sets. Anyone who can read the
repository can download the artifacts: measure pages that set no secret, or set
`upload-artifact: false`.
:::

## Running on self-hosted ARC runners

The `sitespeed` job needs no Docker daemon and no Chrome on the runner: on an ARC
scale set in Kubernetes container mode it runs as a workflow pod of the image. The
`history` job runs on the runner pod itself, which must be allowed
(`ACTIONS_RUNNER_REQUIRE_JOB_CONTAINER=false`).

- **`/dev/shm`**: `docker run --shm-size=1g` used to give Chrome 1 GiB. Under Docker
  the job container still gets it (`--shm-size=1g`), but Kubernetes ignores
  container options: mount an in-memory `emptyDir` on `/dev/shm` in the hook
  template. When `/dev/shm` is under 512 MiB, the job adds
  `--browsertime.chrome.args=disable-dev-shm-usage` itself, and says so.
- **Non-root**: the job runs as the runner's UID, 1001 (`--user 1001` under Docker,
  `runAsUser` in the hook template). The image's entrypoint is skipped, and with it
  its switch from root to the workspace owner: the job is that owner already.
- **Chrome's sandbox**: the image sets `--no-sandbox`
  (`SITESPEED_IO_BROWSERTIME__DOCKER`). The sandbox needs user namespaces or a
  setuid helper, which an unprivileged container cannot offer; the container is
  the boundary, and the token that writes the history never enters it.

The whole list (Pod Security, egress, hook template):
[Running on self-hosted ARC runners](../self-hosted-arc-runners.md).

## Notes

- **Measure from outside the site's own network.** Testing from the network that
  serves the site, such as the cluster that runs it, skews LCP and TTFB; a
  GitHub-hosted runner, or a scale set elsewhere, is the right vantage point.
- The caller's `permissions:` cap the called workflow. Grant `contents: write`
  on the calling job when the history is enabled; with `history-branch: ''`
  `contents: read` is enough.
- The budget file must wrap the thresholds in a top-level `"budget"` key.
- Start with loose thresholds and tighten them after a week of data.
- No dashboard: alerting is the failure email, history is the CSV; the
  artifacts hold the raw results of the recent runs.

## Run locally

```bash
docker run --rm --shm-size=1g -v "$(pwd)/sitespeed-result:/sitespeed.io" \
  sitespeedio/sitespeed.io:<tag> https://example.com/ -n 5 -b chrome \
  --budget.configPath budget.json --plugins.add analysisstorer
```
