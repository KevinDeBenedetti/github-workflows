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

## Manual testing

Use `dry-run: true` before your first real purge to preview exactly what would be deleted.
The `examples/maintenance.yml` caller defaults `dry-run` to `true` when triggered via
**Actions → Maintenance → Run workflow**, so a manual dispatch is always a safe preview
unless you explicitly uncheck the option.

```yaml
on:
  workflow_dispatch:
    inputs:
      keep:
        description: Number of most-recent deployments to keep
        type: number
        default: 10
        required: false
      dry-run:
        description: Preview without deleting
        type: boolean
        default: true
        required: false

jobs:
  purge:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/purge-deployments.yml@main
    with:
      keep: ${{ fromJSON(inputs.keep || '10') }}
      dry-run: ${{ inputs.dry-run == 'true' }}
    secrets: inherit
```

## Schedule

Automate after you're satisfied with a dry-run:

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
