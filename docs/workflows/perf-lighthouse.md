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

| Input                     | Type    | Default                                   | Description                                                                               |
| ------------------------- | ------- | ----------------------------------------- | ----------------------------------------------------------------------------------------- |
| `site`                    | string  | — (required)                              | Site to audit, `http(s)://…`                                                              |
| `urls`                    | string  | `/`                                       | Comma-separated paths to audit, each starting with `/`                                    |
| `config`                  | string  | `""`                                      | Lighthouse CI config in the caller repository; empty measures without assertions          |
| `version-url`             | string  | `""`                                      | JSON document whose `version` is the release tag the site runs; empty: run's commit       |
| `lhci-version`            | string  | `<version>`                               | `@lhci/cli` version, bumped by Renovate                                                   |
| `browser-image`           | string  | `sitespeedio/sitespeed.io:<tag>@sha256:…` | Image the audit runs in, with Node and Chrome, pinned by tag + digest, bumped by Renovate |
| `artifact-retention-days` | number  | `7`                                       | Days the artifact is kept, 1 to 90; the repository's retention setting caps it            |
| `upload-artifact`         | boolean | `true`                                    | `false` uploads nothing to GitHub: a check that only gates on the assertions              |
| `report-s3-endpoint`      | string  | `""`                                      | `https://` URL of an S3-compatible API, for a copy of the reports                         |
| `report-s3-bucket`        | string  | `""`                                      | Bucket of the copy (private, with a lifecycle rule). Empty: no copy                       |
| `report-s3-prefix`        | string  | `""`                                      | Key prefix of the copy, before `<owner>/<repo>/`                                          |
| `runner`                  | string  | `'"ubuntu-26.04"'`                        | Runner labels as JSON                                                                     |

| Secret                        | Description                                                           |
| ----------------------------- | --------------------------------------------------------------------- |
| `report-s3-access-key-id`     | Access key ID of the copy (a B2 application key ID), with a bucket    |
| `report-s3-secret-access-key` | Secret access key of the copy (the B2 application key), with a bucket |

## Jobs

1. **`lighthouse`** — runs inside `browser-image` as the job's container, with a
   read-only token: checks the report inputs and the other inputs, checks out the
   config, runs `lhci collect`, `assert` and `upload --target=filesystem`, uploads
   the `lighthouse-report` artifact and copies it to S3 when asked, then writes the
   scores to the step summary. An `error` assertion that fails fails this job.
2. **`statuses`** — on the runner itself, posts one commit status per page from the
   results of the first job (the `pages` output of
   [`lighthouse-results`](../actions/lighthouse-results.md)). It is the only job
   with `statuses: write`: that token never enters the container where Chrome runs
   pages without its sandbox.

## Reports in S3

With `report-s3-bucket`, the reports go to S3-compatible storage (Backblaze B2,
AWS S3, MinIO), whether or not an artifact is uploaded, under
`<prefix>/<owner>/<repo>/perf-lighthouse/<run id>-<run attempt>/lighthouse-report/`;
the job summary gives the path, and a failed copy fails the job. Make the bucket
**private** with a **lifecycle rule** that deletes the reports after a few days or
weeks: see [`upload-report-s3`](../actions/upload-report-s3.md). The statuses
link to the artifact when there is one, to the run otherwise.

## Running on self-hosted ARC runners

The `lighthouse` job needs neither Chrome nor a Docker daemon on the runner: on an
ARC scale set in Kubernetes container mode it runs as a workflow pod of
`browser-image`. The `statuses` job runs on the runner pod (bash, curl, jq), which
must be allowed (`ACTIONS_RUNNER_REQUIRE_JOB_CONTAINER=false`).

- Chrome starts with `--no-sandbox`: its sandbox needs user namespaces or a setuid
  helper, which an unprivileged container cannot offer. Lighthouse CI adds
  `--headless=new` itself.
- When `/dev/shm` is under 512 MiB (a pod without an in-memory `emptyDir` there),
  Chrome also gets `--disable-dev-shm-usage`.
- These flags replace the config's `ci.collect.settings.chromeFlags`; the flags of
  a JSON config are kept, in front of them.
- The image has no git: the config is checked out through the REST API, with the
  rest of the repository.

The whole list (non-root user, Pod Security, egress, hook template):
[Running on self-hosted ARC runners](../self-hosted-arc-runners.md).

## Notes

- **Permissions**: the calling job grants `contents: read` and `statuses: write`.
  A status GitHub refuses fails no job: the run keeps the audit's result.
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
- **Audit from outside the site's own network**: from the network that serves it,
  such as the cluster that runs it, the scores are skewed.
- Lighthouse scores vary run to run: `numberOfRuns` (3 by default) runs each page
  several times and keeps the median one. Start loose and tighten after a few
  weeks.
- Artifact: `lighthouse-report`, kept `artifact-retention-days` (7 days by
  default), one HTML and one JSON report per run, with `manifest.json`. The
  statuses link to it, so the link of an older status leads to an expired
  artifact. Artifacts count against the account's GitHub Actions storage for
  every hour they exist.

## Run locally

```sh
npm exec --package=@lhci/cli -- lhci collect --config=lighthouserc.json --url=https://example.com/ --startServerCommand=
npm exec --package=@lhci/cli -- lhci assert --config=lighthouserc.json
```
