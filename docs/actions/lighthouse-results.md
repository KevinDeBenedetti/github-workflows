---
title: Action — lighthouse-results
---

# Action — lighthouse-results

Summarizes a Lighthouse CI run in the job summary, one row per page with the
failed categories marked, and posts one commit status per page
(`lighthouse/<path>`) through the GitHub REST API. It reads what `lhci assert`
and `lhci upload --target=filesystem` leave on disk. No third-party service:
Lighthouse CI's own statuses go through its GitHub App or its public report
storage. [`perf-lighthouse.yml`](../workflows/perf-lighthouse.md) runs it after
its audit.

## Usage

```yaml
permissions:
  contents: read
  statuses: write

steps:
  - name: Lighthouse CI
    run: |
      npm exec --yes --package=@lhci/cli -- lhci collect --url=https://example.com/
      status=0
      npm exec --yes --package=@lhci/cli -- lhci assert --config=lighthouserc.json || status=$?
      npm exec --yes --package=@lhci/cli -- lhci upload --target=filesystem --outputDir=.lighthouse
      exit "$status"

  - if: ${{ !cancelled() }}
    uses: KevinDeBenedetti/github-workflows/.github/actions/lighthouse-results@main
```

## Inputs

| Input             | Default                                | Description                                                                |
| ----------------- | -------------------------------------- | -------------------------------------------------------------------------- |
| `report-dir`      | `.lighthouse`                          | Directory written by `lhci upload --target=filesystem`                     |
| `assertions-file` | `.lighthouseci/assertion-results.json` | Results of `lhci assert` (no file when nothing was asserted)               |
| `post-statuses`   | `true`                                 | `false` writes the summary only                                            |
| `sha`             | the run's commit                       | Commit the statuses go on                                                  |
| `version-url`     | `''`                                   | JSON document whose `version` is the release tag the site runs (see below) |
| `target-url`      | `''`                                   | Link of every status, e.g. the report artifact; empty links the run        |
| `context-prefix`  | `lighthouse`                           | Status context before the page path: `lighthouse/en`                       |
| `github-token`    | the job's `GITHUB_TOKEN`               | Token with `statuses: write`, plus `contents: read` for `version-url`      |

## Notes

- A page is `failure` when one of its `error` assertions failed; `warn`
  assertions stay in the report. Results are matched on the URL the page ended
  on, as `lhci assert` keys them, so a redirected page keeps its own status.
- The description lists the category scores, after `Failed N assertion(s) —`
  on a red page, cut at the 140 characters GitHub accepts.
- `version-url`: for a site deployed after the run's commit. The statuses go on
  the commit of the release tag it reports (a bare `1.2.3` is also tried as
  `v1.2.3`). The answer is not trusted: only a tag-shaped `version` is looked up
  and nothing else of it is printed. When it names no tag, no status is posted
  and a warning says so; the summary is still written.
- The token goes through a header file, never on a command line. Needs bash,
  curl and jq: no GitHub CLI.
- Exits `1` when GitHub refuses a status, after trying every page, and `0` with
  a note in the summary when there is no manifest (Lighthouse produced no
  report).
