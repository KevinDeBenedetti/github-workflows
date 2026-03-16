# Purge — Deployments

Deletes all but the **N most-recent deployments** per environment to keep the GitHub deployments list clean.
Deployments are automatically marked **inactive** before deletion (required by the GitHub API).

## Usage

```yaml
jobs:
  purge-deployments:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/purge-deployments.yml@main
    with:
      keep: 10
    secrets: inherit
```

## Inputs

| Input         | Type    | Default | Description                                                                 |
| ------------- | ------- | ------- | --------------------------------------------------------------------------- |
| `keep`        | number  | `10`    | Number of most-recent deployments to keep per environment                   |
| `environment` | string  | `''`    | Environment name to restrict purging (e.g. `production`). Empty = all envs |
| `dry-run`     | boolean | `false` | List what would be deleted without actually deleting anything               |

## Permissions

| Scope         | Level   | Reason                               |
| ------------- | ------- | ------------------------------------ |
| `deployments` | `write` | Mark inactive and delete deployments |
| `contents`    | `read`  | Checkout                             |

## Schedule

Can be called on a schedule from a caller workflow:

```yaml
on:
  schedule:
    - cron: '0 3 * * 0'  # Every Sunday at 03:00 UTC
  workflow_dispatch:

jobs:
  purge:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/purge-deployments.yml@main
    with:
      keep: 10
    secrets: inherit
```

## Notes

- The GitHub API requires deployments to be **inactive** before deletion. The workflow sets each deployment to inactive status first.
- Active deployments (with a current `success` or `in_progress` status) will have a status of `inactive` appended before deletion — this does not affect running deployments.
- A Markdown summary is written to the GitHub Actions job summary after each run.
- Use `dry-run: true` to preview what would be deleted before committing to a purge.
