---
title: Cleanup deployments
---

# Cleanup deployments

Deletes the old deployment records of a repository on a schedule, so that its
Deployments page and its environments show what is deployed, not every deploy
ever made.

A deployment record is what a deploy job leaves behind: an environment, a commit
and statuses. It holds no file and costs no storage. Nothing deployed, no
environment and no secret is touched.

## Usage

```yaml
name: Cleanup deployments

on:
  schedule:
    - cron: "3 5 * * 1"  # Mondays, 05:03 UTC
  workflow_dispatch:

permissions: {}

jobs:
  cleanup:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cleanup-deployments.yml@main
    permissions:
      deployments: write
    with:
      dry-run: true
```

Start in dry-run: run it once by hand from the Actions tab, read what the log
says it would delete, then remove the `dry-run` line.

## What is kept

- Every deployment younger than `older-than-days`.
- The `keep` most recent deployments of each environment, whatever their age:
  the record of what runs there now is always among them.

Every other deployment is deleted, oldest first, `max-deletions` at most per
run. GitHub refuses to delete an active deployment, so each one is first given
the `inactive` status, then deleted. A deleted record cannot be restored.

## Inputs

| Input             | Type    | Default            | Description                                                       |
| ----------------- | ------- | ------------------ | ----------------------------------------------------------------- |
| `keep`            | number  | `5`                | Most recent deployments kept per environment (1 to 100)           |
| `older-than-days` | number  | `30`               | Age, in days, before a deployment can be deleted (0 or more)      |
| `max-deletions`   | number  | `200`              | Deletions at most in one run (1 to 400), two requests each        |
| `dry-run`         | boolean | `false`            | Log what would be deleted, delete nothing                         |
| `runner`          | string  | `'"ubuntu-26.04"'` | Runner labels as JSON; a Linux runner with bash, curl and jq      |

## Permissions

| Permission    | Level   | Why                                                       |
| ------------- | ------- | --------------------------------------------------------- |
| `deployments` | `write` | List the deployments, set them inactive and delete them   |

## Notes

- The job token reaches only its own repository: each repository calls this
  workflow itself. No PAT and no GitHub App.
- A deployment that cannot be set inactive or deleted is skipped with a
  warning. The job fails only when no deletion at all succeeds.
- The work is done by the [`cleanup-deployments`](../actions/cleanup-deployments.md)
  action.
