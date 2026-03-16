# Purge — Caches

Deletes all but the **N most-recently-used caches** to keep Actions cache storage lean.
Caches are ranked by `lastAccessedAt` — the least-recently-used are removed first.

## Usage

```yaml
jobs:
  purge-caches:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/purge-caches.yml@main
    with:
      keep: 10
    secrets: inherit
```

## Inputs

| Input     | Type    | Default | Description                                                                    |
| --------- | ------- | ------- | ------------------------------------------------------------------------------ |
| `keep`    | number  | `10`    | Number of most-recently-used caches to keep                                    |
| `ref`     | string  | `''`    | Git ref to restrict purging (e.g. `refs/heads/main`). Empty = all refs        |
| `dry-run` | boolean | `false` | List what would be deleted without actually deleting anything                  |

## Permissions

| Scope      | Level   | Reason              |
| ---------- | ------- | ------------------- |
| `actions`  | `write` | Delete caches       |
| `contents` | `read`  | Checkout            |

## Manual testing

Use `dry-run: true` before your first real purge to preview exactly which caches would be removed.

```yaml
on:
  workflow_dispatch:
    inputs:
      keep:
        description: Number of most-recently-used caches to keep
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
    uses: KevinDeBenedetti/github-workflows/.github/workflows/purge-caches.yml@main
    permissions:
      actions: write
      contents: read
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
    uses: KevinDeBenedetti/github-workflows/.github/workflows/purge-caches.yml@main
    permissions:
      actions: write
      contents: read
    with:
      keep: 10
    secrets: inherit
```

## Notes

- Caches are sorted by `lastAccessedAt` (most recently used first) — the oldest unused caches are deleted first.
- Use `ref` to scope purging to a single branch, e.g. clean up stale PR caches.
- The job summary reports each deleted cache's key, ref, size, and last-accessed timestamp, plus total storage freed.
- Use `dry-run: true` to preview what would be deleted before committing to a purge.
