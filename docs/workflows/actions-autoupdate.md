# Actions Autoupdate

Scans all workflow files in `.github/` for pinned action versions, bumps them to the latest available release via the GitHub API, and opens a pull request with the changes.

## Usage

```yaml
jobs:
  autoupdate:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/actions-autoupdate.yml@main
    secrets: inherit
```

## Inputs

| Input    | Type   | Default                    | Description                                        |
| -------- | ------ | -------------------------- | -------------------------------------------------- |
| `branch` | string | `chore/actions-autoupdate` | Branch name for the autoupdate PR                  |
| `labels` | string | `''`                       | Comma-separated labels to add to the PR (e.g. `dependencies,chore`) |

## Secrets

| Secret      | Required | Description                                                                                      |
| ----------- | -------- | ------------------------------------------------------------------------------------------------ |
| `PAT_TOKEN` | ✅        | Personal Access Token with `contents:write`, `pull-requests:write`, and `workflows` scope (required to push changes to `.github/workflows/` files) |

## Schedule

This workflow also runs automatically on a built-in schedule (every Monday at 06:00 UTC) when called via `workflow_call` with a `schedule` trigger on the caller side, or when the schedule in this workflow fires directly.

```yaml
on:
  schedule:
    - cron: '0 6 * * 1'
  workflow_dispatch:

jobs:
  autoupdate:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/actions-autoupdate.yml@main
    secrets: inherit
```

## Notes

- Major-only pins (e.g. `@v5`) are only bumped when the major version increases.
- Full semver pins (e.g. `@v1.2.3`) are updated to the exact latest tag.
- If no updates are needed, no PR is opened and the workflow exits cleanly.
- If a PR for the autoupdate branch already exists, it is not duplicated.
