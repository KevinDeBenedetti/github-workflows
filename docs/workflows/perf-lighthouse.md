---
title: Perf — Lighthouse CI
---

# Perf — Lighthouse CI

[Lighthouse CI](https://github.com/GoogleChrome/lighthouse-ci) audits chosen
pages of a **deployed** site and holds them to the thresholds of your Lighthouse
CI config. The job **fails when an `error` assertion fails**, so GitHub's
failure email is the alert. Every page also gets a commit status
(`lighthouse/<path>`) with its scores, posted through the GitHub API by the
[`lighthouse-results`](../actions/lighthouse-results.md) action: no third-party
service is involved. Scores are printed in the step summary and the HTML and
JSON reports are kept as an artifact.

[`perf-unlighthouse.yml`](./perf-unlighthouse.md) crawls every page against one
budget; this workflow checks a fixed list of pages against per-category
assertions and reports each of them on the commit.

## Usage

```yaml
on:
  schedule:
    - cron: "17 5 * * *"
  workflow_dispatch:

jobs:
  lighthouse:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/perf-lighthouse.yml@main
    permissions:
      contents: read # the config, and the commit behind version-url
      statuses: write # one status per page
    with:
      site: https://example.com
      urls: /,/about
      config: lighthouserc.json
      version-url: https://example.com/api/health
```

`lighthouserc.json`, in the caller repository:

```json
{
  "ci": {
    "collect": { "numberOfRuns": 3 },
    "assert": {
      "assertions": {
        "categories:performance": ["error", { "minScore": 0.8 }],
        "categories:accessibility": ["error", { "minScore": 0.9 }]
      }
    }
  }
}
```

## Inputs

| Input          | Type   | Default             | Description                                                                         |
| -------------- | ------ | ------------------- | ----------------------------------------------------------------------------------- |
| `site`         | string | — (required)        | Site to audit, `http(s)://…`                                                        |
| `urls`         | string | `/`                 | Comma-separated paths to audit, each starting with `/`                              |
| `config`       | string | `""`                | Lighthouse CI config in the caller repository; empty measures without assertions    |
| `version-url`  | string | `""`                | JSON document whose `version` is the release tag the site runs; empty: run's commit |
| `lhci-version` | string | `<version>`         | `@lhci/cli` version, bumped by Renovate                                             |
| `runner`       | string | `'"ubuntu-latest"'` | Runner labels as JSON                                                               |

## Notes

- **Permissions**: the calling job grants `contents: read` and `statuses: write`.
  A status GitHub refuses fails the summary step only: the job keeps the audit's
  result.
- **The config**: only that file is checked out. Its `ci.assert` sets the
  thresholds and its `ci.collect` the runs and Lighthouse settings. The pages
  audited are always `site` + `urls`: the config's `url` list and
  `startServerCommand`, meant for a local `lhci autorun`, are overridden, and the
  reports always go to the artifact. See the
  [configuration reference](https://github.com/GoogleChrome/lighthouse-ci/blob/main/docs/configuration.md).
- **Which commit**: the statuses describe the run's commit by default. When the
  site is deployed after that commit (GitOps, a manual merge), set
  `version-url`: the statuses go on the commit of the release tag the site
  reports, so a daily run marks what is actually live. When it names no tag of
  the repository, no status is posted (a warning says so); the summary and the
  artifact stay.
- **Do not use a `k3s-*` runner**: auditing from the site's own network skews
  the scores.
- Lighthouse scores vary run to run: `numberOfRuns` (3 by default) runs each page
  several times and keeps the median one. Start loose and tighten after a few
  weeks.
- Artifact: `lighthouse-report` (30 days), one HTML and one JSON report per run,
  with `manifest.json`.

## Run locally

```sh
npm exec --package=@lhci/cli -- lhci collect --config=lighthouserc.json --url=https://example.com/ --startServerCommand=
npm exec --package=@lhci/cli -- lhci assert --config=lighthouserc.json
```
