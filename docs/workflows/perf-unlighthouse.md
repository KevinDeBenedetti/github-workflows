# Perf — Unlighthouse

[Unlighthouse](https://unlighthouse.dev/) audits **every page** of a site with
Lighthouse (crawl + sitemap) and scores performance, accessibility, best
practices and SEO page by page. The job **fails when any page is under
`budget`**, so GitHub's failure email is the alert. Scores are printed in the
step summary and the full static HTML report is kept as an artifact.

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

| Input                  | Type   | Default            | Description                                                      |
| ---------------------- | ------ | ------------------ | ---------------------------------------------------------------- |
| `site`                 | string | — (required)       | Site to audit, `http(s)://…`                                     |
| `budget`               | number | `75`               | Minimum score (1-100) every page must reach on every category    |
| `device`               | string | `desktop`          | `desktop` or `mobile`                                            |
| `samples`              | number | `1`                | Lighthouse runs per page (averaged)                              |
| `urls`                 | string | `""`               | Comma-separated paths to audit instead of crawling               |
| `exclude-urls`         | string | `""`               | Comma-separated paths or regexes to skip                         |
| `unlighthouse-version` | string | `<version>`        | `@unlighthouse/cli` version, bumped by Renovate                  |
| `runner`               | string | `'"ubuntu-latest"'` | Runner labels as JSON                                           |

## Notes

- **Do not use a `k3s-*` runner**: auditing from the site's own network skews
  the scores.
- Unlighthouse samples dynamic routes (e.g. `/blog/*`) by default, so large
  sites stay affordable. Use `urls` to pin an explicit list.
- For both devices, call the workflow twice (one job per `device`).
- Lighthouse scores vary run to run; raise `samples` or lower `budget` if the
  alert is noisy. Start loose and tighten after a few weeks.
- Artifact: `unlighthouse-report-<device>` (30 days) — open `index.html`.

## Run locally

```bash
npm exec --package=@unlighthouse/cli -- unlighthouse-ci --site https://example.com --budget 75 --build-static
```
