# Dispatch — Docs Rebuild

Sends a `repository_dispatch` event to a target repository (default: `KevinDeBenedetti/kevindebenedetti.github.io`) to trigger a remote documentation rebuild.

## Usage

```yaml
jobs:
  dispatch-docs:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/dispatch-docs.yml@main
    secrets: inherit
```

## Inputs

| Input         | Type   | Default                                    | Description                                          |
| ------------- | ------ | ------------------------------------------ | ---------------------------------------------------- |
| `target-repo` | string | `KevinDeBenedetti/kevindebenedetti.github.io` | Repository to dispatch to (`owner/repo`)           |
| `event-type`  | string | `docs-updated`                             | `repository_dispatch` event type to send             |

## Secrets

| Secret      | Required | Description                                                                  |
| ----------- | -------- | ---------------------------------------------------------------------------- |
| `PAT_TOKEN` | ✅        | Fine-grained PAT with `actions:write` on the **target** repository           |

## Notes

- The dispatch payload includes `source` (the calling repository) and `ref` (the triggering branch/tag).
- The target repository must have a workflow that listens for the `repository_dispatch` event type.
- Designed to be called after a documentation-affecting push to automatically rebuild the docs site.
