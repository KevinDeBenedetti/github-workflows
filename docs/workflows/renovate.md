---
title: '`renovate` workflow'
---

# `renovate` workflow

Runs Renovate on the calling repository from GitHub Actions, with the token of a GitHub
App: no Marketplace app to install, and the update pull requests run CI like any other
(those of a `GITHUB_TOKEN` would not). The repository's `renovate.json` decides what is
updated and when; it extends the [shared preset](#the-shared-preset).

## Usage

```yaml
# .github/workflows/renovate.yml  (in your repo)
name: Renovate

on:
  schedule:
    - cron: "17 1 * * *"  # every day, 01:17 UTC: well inside the Monday-morning schedule
  workflow_dispatch:
    inputs:
      dry-run:
        description: Look the updates up and log them, change nothing on GitHub
        type: boolean
        default: true

permissions: {}

jobs:
  renovate:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/renovate.yml@main
    permissions: {}
    with:
      app-client-id: ${{ vars.RELEASE_APP_CLIENT_ID }}
      dry-run: ${{ inputs.dry-run == true }}  # false on a schedule
    secrets:
      APP_PRIVATE_KEY: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}
```

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["github>KevinDeBenedetti/renovate-config"]
}
```

`renovate.json` goes at the root of the repository. The config's `schedule` decides
when pull requests open: the daily
run only keeps the Dependency Dashboard's checkboxes and the open pull requests current
in between. Keep the cron well inside the schedule: GitHub starts a scheduled run late
under load, and a run after 6am Paris time opens nothing that week.

## The shared preset

[`KevinDeBenedetti/renovate-config`](https://github.com/KevinDeBenedetti/renovate-config),
a public repository, so the App token minted for the calling repository can read it.
Its README lists what it sets: Renovate's best practices, the Monday-morning window in
Paris time, a 3-day release age, OSV security updates, prek hook revs, every update
(majors included, security fixes aside) in one weekly pull request, labels, majors
of data-owning images held for approval, and `KevinDeBenedetti/github-workflows` left
to [`propagate-release`](./propagate-release.md). Without a tag, Renovate reads it from
its `main` branch.

The repository's `renovate.json` adds what is its own: the base branch, groups, commit
types. Its `packageRules` come after the preset's, so they win: a `groupName` there
takes its packages out of the weekly pull request into one of their own.

::: warning Release dates
With `minimumReleaseAge`, an update whose datasource gives no release date never
passes: `minimumReleaseAgeBehaviour` defaults to `timestamp-required`. Docker images
get one on Docker Hub only. For an image of another registry, such as
`mcr.microsoft.com`, set `"minimumReleaseAgeBehaviour": "timestamp-optional"` in a
`packageRules` entry that matches it.
:::

## Set up

1. A GitHub App with **Contents**, **Issues**, **Pull requests**, **Workflows** and
   **Commit statuses** set to *Read and write*, and **Dependabot alerts** set to *Read-only*,
   installed on the repository. Commit statuses carry Renovate's `renovate/stability-days`
   check, and Dependabot alerts let it open security pull requests: without either, the
   token is refused, with "The permissions requested are not granted to this
   installation". After adding a permission to the App, accept it on the installation.
2. In the repository, the App's client ID as a variable and its private key as a
   secret. The usage above takes those of the App of
   [`propagate-release`](./propagate-release.md).
3. The `renovate.json` above, on the default branch: Renovate reads its config from
   there only. A repository without one is skipped, with no onboarding pull request.
4. A manual run, a dry run by default in the usage above: its log lists the updates
   Renovate found. A run with the box unticked still opens pull requests only inside
   the `schedule`, or for the updates ticked in the Dependency Dashboard.
5. When the repository runs [`check-bot-commits`](./check-bot-commits.md), add the App's
   bot, `<app-slug>[bot]`, to `allowed-bots`.

## Inputs

| Input           | Type    | Default            | Description                                                  |
| --------------- | ------- | ------------------ | ------------------------------------------------------------ |
| `app-client-id` | string  | required           | Client ID of the GitHub App installed on the repository      |
| `dry-run`       | boolean | `false`            | Look the updates up and log them, change nothing on GitHub   |
| `log-level`     | string  | `info`             | Renovate log level: `debug`, `info`, `warn`                  |
| `runner`        | string  | `'"ubuntu-26.04"'` | Runner labels as JSON; Linux with a Docker daemon            |

## Secrets

| Secret            | Required | Description                   |
| ----------------- | -------- | ----------------------------- |
| `APP_PRIVATE_KEY` | yes      | Private key of the GitHub App |

## Permissions

- The calling job grants nothing: Renovate works with the App's token, created for the
  calling repository only, with `contents`, `issues`, `pull-requests`, `statuses` and
  `workflows` write and `vulnerability-alerts` read, and expiring with the job.

## Notes

- Renovate runs in its container image, pinned in the workflow and bumped by this
  repository's own Renovate, which reads the version from Renovate's GitHub releases
  (the image itself has no release date). The runner needs a Docker daemon.
- Commits go through the API (`platformCommit`), so GitHub signs them; the App is their
  author.
- One run at a time per repository: a manual run waits for the scheduled one.
- The `renovate-config-validator` hook of `renovatebot/pre-commit-hooks` checks
  `renovate.json` before a commit, and [`ci-prek`](./ci-prek.md) runs it in CI.
