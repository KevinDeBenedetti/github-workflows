# Purge — Workflow Runs

Deletes all but the **N most-recent runs** per workflow to keep the GitHub Actions run history manageable.

## Usage

```yaml
jobs:
  purge-workflow-runs:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/purge-workflow-runs.yml@main
    with:
      keep: 10
    secrets: inherit
```

## Inputs

| Input      | Type    | Default | Description                                                                                   |
| ---------- | ------- | ------- | --------------------------------------------------------------------------------------------- |
| `keep`     | number  | `10`    | Number of most-recent runs to keep per workflow                                               |
| `workflow` | string  | `''`    | Workflow filename to restrict purging (e.g. `ci-node.yml`). Empty = all workflows             |
| `status`   | string  | `''`    | Only delete runs with this status (`completed`, `failure`, `cancelled`, `skipped`). Empty = all |
| `dry-run`  | boolean | `false` | List what would be deleted without actually deleting anything                                 |

## Permissions

| Scope      | Level   | Reason                   |
| ---------- | ------- | ------------------------ |
| `actions`  | `write` | Delete workflow runs     |
| `contents` | `read`  | Checkout                 |

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
        description: Number of most-recent runs to keep per workflow
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
    uses: KevinDeBenedetti/github-workflows/.github/workflows/purge-workflow-runs.yml@main
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
    uses: KevinDeBenedetti/github-workflows/.github/workflows/purge-workflow-runs.yml@main
    with:
      keep: 10
    secrets: inherit
```

## Notes

- Runs are fetched from the GitHub API in newest-first order; the oldest runs beyond `keep` are deleted.
- When `workflow` is empty, all workflows in the repository are processed in sequence.
- A Markdown summary is written to the GitHub Actions job summary after each run.
- Use `dry-run: true` to preview what would be deleted before committing to a purge.
