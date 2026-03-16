# Label Sync

Syncs a `labels.yml` file in the caller repository to GitHub labels via the Issues API.
Labels not present in the file are left untouched; labels in the file are created or updated.

## Usage

```yaml
jobs:
  label-sync:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/label-sync.yml@main
    secrets: inherit
```

## Inputs

| Input         | Type   | Default      | Description                                        |
| ------------- | ------ | ------------ | -------------------------------------------------- |
| `labels-path` | string | `labels.yml` | Path to the labels definition file in the caller repo |

## Secrets

| Secret  | Required | Description                                                        |
| ------- | -------- | ------------------------------------------------------------------ |
| `token` | ❌        | PAT with `issues:write`. Falls back to `GITHUB_TOKEN` if not set  |

## Permissions

| Scope      | Level   | Reason              |
| ---------- | ------- | ------------------- |
| `contents` | `read`  | Checkout            |
| `issues`   | `write` | Create/update labels |

## Notes

- Uses the sync script from `KevinDeBenedetti/github-workflows` — no additional setup required in the caller.
- The `labels.yml` format should be a list of label objects: `name`, `color`, `description`.
- Designed to be triggered on pushes to the default branch whenever `labels.yml` changes.
