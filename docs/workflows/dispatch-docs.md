# Deploy — Docs to Central Repo

Triggers a rebuild of the centralized docs site (`KevinDeBenedetti/kevindebenedetti.github.io`)
by dispatching a `repository_dispatch` event (`docs-updated`). The central site's own
`sync-docs.ts` re-clones the latest `docs/` from every public repo at build time.

## Usage

```yaml
jobs:
  deploy-docs:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-docs.yml@main
    with:
      app-id: ${{ vars.DOCS_APP_ID }}
    secrets:
      APP_PRIVATE_KEY: ${{ secrets.DOCS_APP_PRIVATE_KEY }}
```

## Inputs

| Input              | Type   | Default                                         | Description                                                                        |
| ------------------ | ------ | ----------------------------------------------- | ---------------------------------------------------------------------------------- |
| `docs-directory`   | string | `docs`                                          | Docs folder in the calling repo (sent as metadata in the dispatch payload)         |
| `target-repo`      | string | `KevinDeBenedetti/kevindebenedetti.github.io`   | Centralized docs repository (`owner/repo`) that receives the dispatch event        |
| `target-directory` | string | _(calling repo name)_                           | Logical name for this repo's docs section (sent as metadata in the dispatch payload) |
| `app-id`           | string | _(required)_                                    | ID of the GitHub App installed on `target-repo` (e.g. <code v-pre>${{ vars.DOCS_APP_ID }}</code>) |

## Outputs

| Output        | Description                                                        |
| ------------- | ------------------------------------------------------------------ |
| `docs-synced` | `"true"` when the `docs-updated` event was dispatched successfully |

## Secrets

| Secret            | Required | Description                                                                                |
| ----------------- | -------- | ------------------------------------------------------------------------------------------ |
| `APP_PRIVATE_KEY` | ✅        | Private key of the GitHub App (`app-id`) installed on the **target** repository with `contents: read and write` permission |

## How it works

1. Resolves the target directory name (defaults to the calling repo name).
2. Mints a short-lived (1 h) installation token via `actions/create-github-app-token`,
   scoped to `contents:write` on `target-repo` only.
3. Sends a `repository_dispatch` event (`docs-updated`) to `target-repo` via the GitHub API.
4. The dispatch payload includes:
   - `repo` — full name of the calling repo (`owner/repo`)
   - `ref` — branch/tag that triggered the dispatch
   - `sha` — commit SHA at time of dispatch
   - `docs_directory` — path to the docs folder in the source repo
   - `target_directory` — logical name for this repo's section in the central site
5. The central repo's CI/CD picks up the `docs-updated` event and rebuilds the VitePress site.
   Its `sync-docs.ts` re-clones `docs/` from all public repos (including the calling repo)
   before the build.

## Notes

- No files are committed directly to `target-repo` — the central site's build handles all syncing.
- The GitHub App must be installed on `target-repo` with `Contents: Read and write` permission.
  Store its ID as the `DOCS_APP_ID` repository variable and its private key as the
  `DOCS_APP_PRIVATE_KEY` secret in every calling repo.
- The central repo must have `repository_dispatch: types: [docs-updated]` in its CI trigger.
