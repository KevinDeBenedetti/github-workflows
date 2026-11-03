---
title: '`cleanup-runs` workflow'
---

# `cleanup-runs` workflow

Deletes the old workflow runs of a repository, with their logs and artifacts, on a
schedule, with one retention policy for every repository. Recent runs, the last runs
of each workflow and the runs of open pull requests are never deleted.

## Usage

```yaml
# .github/workflows/cleanup-runs.yml  (in your repo)
name: Cleanup workflow runs

on:
  schedule:
    - cron: "43 4 * * 1"  # Mondays, 04:43 UTC
  workflow_dispatch:

permissions: {}

jobs:
  cleanup:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cleanup-runs.yml@main
    permissions:
      actions: write
      pull-requests: read
    with:
      dry-run: true
```

Start in dry-run: run the workflow once by hand from the Actions tab, read what the
log and the job summary say it would delete, then remove the `dry-run` line so the
weekly run deletes.

### With the GHCR cleanup

A repository that publishes images can run both cleanups from one weekly file:

```yaml
jobs:
  runs:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cleanup-runs.yml@main
    permissions:
      actions: write
      pull-requests: read
  images:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cleanup-ghcr.yml@main
    permissions:
      packages: write
```

See [`cleanup-ghcr`](./cleanup-ghcr.md) for the image retention.

## Retention policy

The policy is set once, in this workflow, for every caller. A run is kept when any of
these holds:

- it is not completed: queued, running, or waiting for an approval;
- it was created less than `older-than-days` days ago, counted in whole UTC days;
- it is among the `keep-runs` most recent runs of its workflow, whatever its age;
- its commit is the head of an open pull request, or the commit the cleanup runs on
  (on a schedule, the last commit of the default branch): their checks stay visible.

Every other run is deleted, oldest first, with its logs and artifacts.

- A workflow whose file was deleted keeps no run: once its last run is older than
  `older-than-days`, it leaves the Actions sidebar.
- The workflows GitHub runs by itself, such as Dependabot updates, keep their last
  runs like the others.
- One run deletes at most `max-deletions` runs. A larger backlog, such as the first
  run on an old repository, goes over the next weekly runs: the job summary says how
  many are left. GitHub also lists at most 1,000 runs per query, so beyond 1,000 old
  runs the next runs look further.

## Inputs

| Input             | Type    | Default             | Description                                                         |
| ----------------- | ------- | ------------------- | ------------------------------------------------------------------- |
| `keep-runs`       | number  | `10`                | Most recent runs kept per workflow, whatever their age (0 to 100)   |
| `older-than-days` | number  | `30`                | Age, in days, before a run can be deleted (1 or more)               |
| `max-deletions`   | number  | `500`               | Runs deleted at most in one run (1 to 1000)                         |
| `dry-run`         | boolean | `false`             | Log what would be deleted, delete nothing                           |
| `runner`          | string  | `'"ubuntu-latest"'` | Runner labels as JSON; a Linux runner with bash, curl and jq        |

## Permissions

- The calling job grants `actions: write`, to list and delete the runs, and
  `pull-requests: read`, to find the open pull requests. The workflow uses the
  caller's `GITHUB_TOKEN`: no personal access token and no GitHub App.
- A `GITHUB_TOKEN` reaches only its own repository: every repository calls the
  workflow for its own runs.
- A caller that grants less fails at startup: a reusable workflow never gets more
  than its caller grants.

## Notes

- A deleted run cannot be restored, nor its logs and artifacts.
- The deletions are one second apart, as GitHub asks for, and capped by
  `max-deletions`: a `GITHUB_TOKEN` may send 1,000 REST requests an hour per
  repository. 500 deletions take about ten minutes.
- One run at a time per repository.
- The logs and artifacts of the runs kept still expire after the repository's
  retention period (**Settings → Actions → General → Artifact and log retention**,
  90 days by default); the run itself stays listed until it is deleted.
- The [`cleanup-runs` action](../actions/cleanup-runs.md) does the work and can run
  in a job of your own.
