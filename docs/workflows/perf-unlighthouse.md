---
title: Perf — Unlighthouse
---

# Perf — Unlighthouse

[Unlighthouse](https://unlighthouse.dev/) audits **every page** of a site with
Lighthouse (crawl + sitemap) and scores performance, accessibility, best
practices and SEO page by page. The job **fails when any page is under
`budget`**, so GitHub's failure email is the alert. Scores are printed in the
step summary and the full static HTML report is kept as an artifact, or copied
to S3-compatible storage. Unlighthouse and its Chrome run inside a pinned image
as the job's container: the runner needs neither Chrome nor a Docker daemon.

## Usage

```yaml
on:
  schedule:
    - cron: "43 5 * * 1"
  workflow_dispatch:

jobs:
  unlighthouse:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/perf-unlighthouse.yml@main
    permissions:
      contents: read
    with:
      site: https://example.com
      budget: 80
```

## Inputs

| Input                     | Type    | Default                                   | Description                                                                               |
| ------------------------- | ------- | ----------------------------------------- | ----------------------------------------------------------------------------------------- |
| `site`                    | string  | — (required)                              | Site to audit, `http(s)://…`                                                              |
| `budget`                  | number  | `75`                                      | Minimum score (1-100) every page must reach on every category                             |
| `device`                  | string  | `desktop`                                 | `desktop` or `mobile`                                                                     |
| `samples`                 | number  | `1`                                       | Lighthouse runs per page (averaged)                                                       |
| `urls`                    | string  | `""`                                      | Comma-separated paths to audit instead of crawling                                        |
| `exclude-urls`            | string  | `""`                                      | Comma-separated paths or regexes to skip                                                  |
| `unlighthouse-version`    | string  | `<version>`                               | `@unlighthouse/cli` version, bumped by Renovate                                           |
| `browser-image`           | string  | `sitespeedio/sitespeed.io:<tag>@sha256:…` | Image the audit runs in, with Node and Chrome, pinned by tag + digest, bumped by Renovate |
| `artifact-retention-days` | number  | `7`                                       | Days the artifact is kept, 1 to 90; the repository's retention setting caps it            |
| `upload-artifact`         | boolean | `true`                                    | `false` uploads nothing to GitHub: a check that only gates on the budget                  |
| `report-s3-endpoint`      | string  | `""`                                      | `https://` URL of an S3-compatible API, for a copy of the report                          |
| `report-s3-bucket`        | string  | `""`                                      | Bucket of the copy (private, with a lifecycle rule). Empty: no copy                       |
| `report-s3-prefix`        | string  | `""`                                      | Key prefix of the copy, before `<owner>/<repo>/`                                          |
| `runner`                  | string  | `'"ubuntu-26.04"'`                        | Runner labels as JSON                                                                     |

| Secret                        | Description                                                           |
| ----------------------------- | --------------------------------------------------------------------- |
| `report-s3-access-key-id`     | Access key ID of the copy (a B2 application key ID), with a bucket    |
| `report-s3-secret-access-key` | Secret access key of the copy (the B2 application key), with a bucket |

## Reports in S3

With `report-s3-bucket`, the report goes to S3-compatible storage (Backblaze B2,
AWS S3, MinIO), whether or not an artifact is uploaded, under
`<prefix>/<owner>/<repo>/perf-unlighthouse/<run id>-<run attempt>/unlighthouse-report-<device>/`:
two calls of one run, one per device, never write over each other. The job
summary gives the path, and a failed copy fails the job. Make the bucket
**private** with a **lifecycle rule** that deletes the reports after a few days or
weeks: see [`upload-report-s3`](../actions/upload-report-s3.md).

## Running on self-hosted ARC runners

The job needs neither Chrome nor a Docker daemon on the runner: on an ARC scale set
in Kubernetes container mode it runs as a workflow pod of `browser-image`, as the
runner's UID (1001) set by the hook template.

- Chrome starts with `--no-sandbox` and `--disable-setuid-sandbox`, passed through
  a generated Unlighthouse config file (`puppeteerOptions.args`): its sandbox needs
  user namespaces or a setuid helper, which an unprivileged container cannot offer,
  and Unlighthouse adds those flags only when it runs as root.
- When `/dev/shm` is under 512 MiB (a pod without an in-memory `emptyDir` there),
  Chrome also gets `--disable-dev-shm-usage`.

The whole list (Pod Security, egress, hook template):
[Running on self-hosted ARC runners](../self-hosted-arc-runners.md).

## Notes

- **Audit from outside the site's own network**: from the network that serves it,
  such as the cluster that runs it, the scores are skewed.
- Unlighthouse samples dynamic routes (e.g. `/blog/*`) by default, so large
  sites stay affordable. Use `urls` to pin an explicit list.
- For both devices, call the workflow twice (one job per `device`).
- Lighthouse scores vary run to run; raise `samples` or lower `budget` if the
  alert is noisy. Start loose and tighten after a few weeks.
- Artifact: `unlighthouse-report-<device>`, kept `artifact-retention-days` (7
  days by default) — open `index.html`. Artifacts count against the account's
  GitHub Actions storage for every hour they exist.

## Run locally

```bash
npm exec --package=@unlighthouse/cli -- unlighthouse-ci --site https://example.com --budget 75 --build-static
```
