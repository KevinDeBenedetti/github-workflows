---
title: Action — cleanup-runs
---

# Action — cleanup-runs

Deletes the old workflow runs of the repository, with their logs and artifacts, oldest
first, and keeps the recent ones. Talks to the REST API with curl and jq: no GitHub CLI
needed, no checkout. [`cleanup-runs.yml`](../workflows/cleanup-runs.md) wraps it and
documents the retention policy.

## Usage

```yaml
permissions:
  actions: write
  pull-requests: read

steps:
  - uses: KevinDeBenedetti/github-workflows/.github/actions/cleanup-runs@main
    with:
      keep-runs: 5
      dry-run: true
```

## Inputs

| Input             | Default                                | Description                                                       |
| ----------------- | -------------------------------------- | ----------------------------------------------------------------- |
| `keep-runs`       | `10`                                   | Most recent runs kept per workflow, whatever their age (0 to 100) |
| `older-than-days` | `30`                                   | Age, in days, before a run can be deleted (1 or more)             |
| `max-deletions`   | `500`                                  | Runs deleted at most in one run (1 to 1000)                       |
| `dry-run`         | `false`                                | Log what would be deleted, delete nothing                         |
| `github-token`    | <code v-pre>${{ github.token }}</code> | Token with `actions: write` and `pull-requests: read`             |

## Outputs

| Output      | Description                                                      |
| ----------- | ---------------------------------------------------------------- |
| `deleted`   | Runs deleted by this run (in a dry run, the runs that would be)  |
| `remaining` | Runs left for a later run by `max-deletions`                     |

## Notes

- The token goes to curl through a header file, never on a command line.
- Workflow paths are printed with any character outside letters, digits and `._/@-`
  replaced by `_`: a workflow file cannot write a workflow command into the log.
- The rules are documented at the top of `cleanup-runs.sh`, and the deletions are
  counted per workflow in the job summary.
