---
title: Action — cleanup-runs
---

# Action — cleanup-runs

Deletes the old workflow runs of the repository, with their logs and artifacts, oldest
first, and keeps the recent ones. With `artifacts-older-than-days`, it also deletes the
old artifacts of the runs it keeps. Talks to the REST API with curl and jq: no GitHub
CLI needed, no checkout. [`cleanup-runs.yml`](../workflows/cleanup-runs.md) wraps it
and documents the retention policy.

## Usage

```yaml
permissions:
  actions: write
  pull-requests: read

steps:
  - uses: KevinDeBenedetti/github-workflows/.github/actions/cleanup-runs@main
    with:
      keep-runs: 5
      artifacts-older-than-days: 3
      dry-run: true
```

## Inputs

| Input                       | Default                                | Description                                                                                                |
| --------------------------- | -------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `keep-runs`                 | `10`                                   | Most recent runs kept per workflow, whatever their age (0 to 100)                                          |
| `older-than-days`           | `30`                                   | Age, in days, before a run can be deleted (1 or more)                                                      |
| `artifacts-older-than-days` | `0`                                    | Age, in days, before an artifact is deleted on its own, its run kept or not (0 to 36500); `0` turns it off |
| `max-deletions`             | `500`                                  | Deletions at most in one run, artifacts first, then runs (1 to 1000)                                       |
| `dry-run`                   | `false`                                | Log what would be deleted, delete nothing                                                                  |
| `github-token`              | <code v-pre>${{ github.token }}</code> | Token with `actions: write` and `pull-requests: read`                                                      |

## Outputs

| Output                  | Description                                                                                                             |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `deleted`               | Runs deleted by this run (in a dry run, the runs that would be)                                                         |
| `remaining`             | Runs left for a later run by `max-deletions`                                                                            |
| `artifacts-deleted`     | Artifacts deleted on their own by this run (in a dry run, the artifacts that would be); one already gone is not counted |
| `artifacts-bytes-freed` | Total size, in bytes, of those artifacts                                                                                |

## Notes

- The token goes to curl through a header file, never on a command line.
- Workflow paths and artifact names are printed with any character outside letters,
  digits and `._/@-` replaced by `_`: a workflow file cannot write a workflow command
  into the log.
- The rules are documented at the top of `cleanup-runs.sh`. The job summary counts
  the runs deleted per workflow and gives the space the artifacts freed, in MB.
- The artifacts of a run not completed are never deleted. Finding those runs takes
  five more requests, one per status (`queued`, `in_progress`, `waiting`, `requested`,
  `pending`), sent only when an artifact is old enough to go.
