# SEO — Crawl

SEO crawl of a live site, in one job:

1. **Broken links and redirects** — [linkinator](https://github.com/JustinBeckwith/linkinator)
   crawls the site recursively. Broken links **fail the job** (GitHub's failure
   email is the alert).
2. **On-page tags** — a small built-in crawler (sitemap + internal links)
   reports, per page: missing or duplicate `<title>`, missing or duplicate meta
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

| Input                | Type    | Default             | Description                                                    |
| -------------------- | ------- | ------------------- | -------------------------------------------------------------- |
| `site`               | string  | — (required)        | Site to crawl, `http(s)://…`                                   |
| `max-pages`          | number  | `500`               | Maximum pages visited by the tag crawler                       |
| `check-external`     | boolean | `true`              | Also check links to other domains                              |
| `skip`               | string  | `""`                | Comma-separated regexes of URLs linkinator skips               |
| `redirects`          | string  | `warn`              | `allow`, `warn` (log them) or `error` (treat as broken)        |
| `fail-on-tag-issues` | boolean | `false`             | Fail on missing/duplicate tags instead of warning              |
| `linkinator-version` | string  | `<version>`         | linkinator version, bumped by Renovate                         |
| `runner`             | string  | `'"ubuntu-latest"'` | Runner labels as JSON                                          |

## Notes

- **Do not use a `k3s-*` runner**: crawl from outside so the result matches
  what search engines see.
- Both checks always run, then the job fails if either failed, so the reports
  and the artifact (`seo-crawl-result`, 30 days) exist even on failure.
- External links are the main source of noise (rate limits, bot blocking).
  Use `skip` for known offenders or `check-external: false`.
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
npm exec --package=linkinator -- linkinator https://example.com --recurse --redirects warn
```
