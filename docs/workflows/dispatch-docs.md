# Deploy — Docs to Central Repo

Triggers a rebuild of the centralized docs site (`KevinDeBenedetti/kevindebenedetti.github.io`)
by dispatching a `repository_dispatch` event (`docs-updated`). The central site's own
`sync-docs.ts` re-clones the latest `docs/` from every public repo at build time.

## Usage

```yaml
jobs:
  deploy-docs:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-docs.yml@main
    secrets: inherit
```

## Inputs

| Input              | Type   | Default                                         | Description                                                                        |
| ------------------ | ------ | ----------------------------------------------- | ---------------------------------------------------------------------------------- |
| `docs-directory`   | string | `docs`                                          | Docs folder in the calling repo (sent as metadata in the dispatch payload)         |
| `target-repo`      | string | `KevinDeBenedetti/kevindebenedetti.github.io`   | Centralized docs repository (`owner/repo`) that receives the dispatch event        |
| `target-directory` | string | _(calling repo name)_                           | Logical name for this repo's docs section (sent as metadata in the dispatch payload) |

## Outputs

| Output        | Description                                                        |
| ------------- | ------------------------------------------------------------------ |
| `docs-synced` | `"true"` when the `docs-updated` event was dispatched successfully |

## Secrets

| Secret      | Required | Description                                                                                |
| ----------- | -------- | ------------------------------------------------------------------------------------------ |
| `PAT_TOKEN` | ✅        | Fine-grained PAT with `contents:write` on the **target** repository (required to send `repository_dispatch`) |

## How it works

1. Resolves the target directory name (defaults to the calling repo name).
2. Sends a `repository_dispatch` event (`docs-updated`) to `target-repo` via the GitHub API.
3. The dispatch payload includes:
   - `repo` — full name of the calling repo (`owner/repo`)
   - `ref` — branch/tag that triggered the dispatch
   - `sha` — commit SHA at time of dispatch
   - `docs_directory` — path to the docs folder in the source repo
   - `target_directory` — logical name for this repo's section in the central site
4. The central repo's CI/CD picks up the `docs-updated` event and rebuilds the VitePress site.
   Its `sync-docs.ts` re-clones `docs/` from all public repos (including the calling repo)
   before the build.

## Notes

- No files are committed directly to `target-repo` — the central site's build handles all syncing.
- `PAT_TOKEN` must have `contents:write` (fine-grained) or `repo` (classic) scope on `target-repo`.
- The central repo must have `repository_dispatch: types: [docs-updated]` in its CI trigger.
