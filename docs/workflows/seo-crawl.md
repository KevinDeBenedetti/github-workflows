---
title: SEO — Crawl
---

# SEO — Crawl

SEO crawl of a live site, in one job:

1. **Broken links and redirects** — [linkinator](https://github.com/JustinBeckwith/linkinator)
   crawls the site recursively. Broken links **fail the job** (GitHub's failure
   email is the alert).
2. **On-page tags** — a small built-in crawler (sitemap + internal links,
   five pages at a time) reports, per page: missing or duplicate `<title>`, missing or duplicate meta
   description, missing or multiple `<h1>`, missing canonical. These are
   **warnings** in the step summary unless `fail-on-tag-issues` is `true`.

It complements [perf-unlighthouse](perf-unlighthouse.md), which scores pages
but detects neither broken links nor duplicate tags.

## Usage

```yaml
on:
  schedule:
    - cron: "11 6 * * 1"
  workflow_dispatch:

jobs:
  seo:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/seo-crawl.yml@main
    permissions:
      contents: read
    with:
      site: https://example.com
```

## Inputs

| Input                     | Type    | Default            | Description                                                                    |
| ------------------------- | ------- | ------------------ | ------------------------------------------------------------------------------ |
| `site`                    | string  | — (required)       | Site to crawl, `http(s)://…`                                                   |
| `max-pages`               | number  | `500`              | Maximum pages visited by the tag crawler                                       |
| `check-external`          | boolean | `true`             | Also check links to other domains                                              |
| `skip`                    | string  | `""`               | Comma-separated regexes of URLs linkinator skips                               |
| `redirects`               | string  | `warn`             | `allow`, `warn` (log them) or `error` (treat as broken)                        |
| `retries`                 | number  | `3`                | Retries of a timed-out, failed, 5xx or 429 link; `0` disables                  |
| `fail-on-tag-issues`      | boolean | `false`            | Fail on missing/duplicate tags instead of warning                              |
| `linkinator-version`      | string  | `<version>`        | linkinator version, bumped by Renovate                                         |
| `artifact-retention-days` | number  | `7`                | Days the artifact is kept, 1 to 90; the repository's retention setting caps it |
| `upload-artifact`         | boolean | `true`             | `false` uploads nothing to GitHub: a check that only gates on broken links     |
| `report-s3-endpoint`      | string  | `""`               | `https://` URL of an S3-compatible API, for a copy of the reports              |
| `report-s3-bucket`        | string  | `""`               | Bucket of the copy (private, with a lifecycle rule). Empty: no copy            |
| `report-s3-prefix`        | string  | `""`               | Key prefix of the copy, before `<owner>/<repo>/`                               |
| `runner`                  | string  | `'"ubuntu-26.04"'` | Runner labels as JSON                                                          |

| Secret                        | Description                                                           |
| ----------------------------- | --------------------------------------------------------------------- |
| `report-s3-access-key-id`     | Access key ID of the copy (a B2 application key ID), with a bucket    |
| `report-s3-secret-access-key` | Secret access key of the copy (the B2 application key), with a bucket |

## Reports in S3

With `report-s3-bucket`, the reports go to S3-compatible storage (Backblaze B2,
AWS S3, MinIO), whether or not an artifact is uploaded, under
`<prefix>/<owner>/<repo>/seo-crawl/<run id>-<run attempt>/seo-crawl-result/`; the
job summary gives the path, and a failed copy fails the job. Make the bucket
**private** with a **lifecycle rule** that deletes the reports after a few days or
weeks: see [`upload-report-s3`](../actions/upload-report-s3.md).

## Running on self-hosted ARC runners

No browser is involved: the job runs on the runner itself, with Node from
`actions/setup-node` (downloaded into the tool cache, no root), jq and the shell's
tools, which the official `actions-runner` image has. On an ARC scale set in
Kubernetes container mode it runs on the runner pod, which must be allowed
(`ACTIONS_RUNNER_REQUIRE_JOB_CONTAINER=false`), with egress on 443 to the crawled
site, `registry.npmjs.org` and GitHub. See
[Running on self-hosted ARC runners](../self-hosted-arc-runners.md).

## Notes

- **Crawl from outside the site's own network**, so the result matches what search
  engines see.
- Both checks always run, then the job fails if either failed, so the reports
  and the artifact (`seo-crawl-result`, kept `artifact-retention-days`, 7 days
  by default) exist even on failure.
- External links are the main source of noise (rate limits, bot blocking,
  hosts briefly down). Each request times out after 30 s, and a link that
  times out, fails to connect or answers a 5xx or a 429 is retried `retries`
  times, with backoff (2 s, 4 s, 8 s… plus up to 3 s of jitter), before it
  counts as broken. Other errors such as a 403 are not retried: use `skip` for
  hosts that always block crawlers, or `check-external: false`.
- Duplicates are computed on indexable pages only (`noindex` pages and error
  pages are ignored). `/` and `/index.html` both being linked is reported as a
  duplicate — that is a real duplicate-content signal, fix it with a canonical
  or a redirect.
- The tag crawler uses regexes, not a browser: it does not see tags injected by
  JavaScript (pure SPAs). Prefer SSR/prerendered output for SEO anyway.
- `redirects: warn` logs redirects without failing; `error` makes every
  redirect (including `http` → `https` and trailing-slash ones) a failure.

## Run locally

```bash
npm exec --package=linkinator -- linkinator https://example.com --recurse --redirects warn \
  --timeout 30000 --retry-errors --retry-errors-count 3
```
