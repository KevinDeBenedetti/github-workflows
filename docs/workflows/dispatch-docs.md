# Deploy — Docs to Central Repo

Syncs the `docs/` folder from the calling repository into a subdirectory of a centralized docs repository (default: `KevinDeBenedetti/kevindebenedetti.github.io`). The central repo is responsible for its own Pages deployment.

## Usage

```yaml
jobs:
  deploy-docs:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-docs.yml@main
    secrets: inherit
```

By default the docs are pushed to a folder named after the calling repository (e.g. a repo named `my-app` → `kevindebenedetti.github.io/my-app/`).

## Inputs

| Input              | Type   | Default                                         | Description                                                                  |
| ------------------ | ------ | ----------------------------------------------- | ---------------------------------------------------------------------------- |
| `docs-directory`   | string | `docs`                                          | Path to the docs folder in the calling repo                                  |
| `target-repo`      | string | `KevinDeBenedetti/kevindebenedetti.github.io`   | Centralized docs repository (`owner/repo`)                                   |
| `target-directory` | string | _(calling repo name)_                           | Subdirectory in the target repo to sync into. Defaults to the repo name.     |

## Outputs

| Output        | Description                                                    |
| ------------- | -------------------------------------------------------------- |
| `docs-synced` | `"true"` if docs were changed and pushed, `"false"` otherwise  |

## Secrets

| Secret      | Required | Description                                                                              |
| ----------- | -------- | ---------------------------------------------------------------------------------------- |
| `PAT_TOKEN` | ✅        | Fine-grained PAT with `contents:write` on the **target** (central) repository. Used both to push synced docs and to dispatch the `docs-updated` event. |

## How it works

1. Checks out the calling repository to read `docs/`.
2. Checks out the central repo (`target-repo`) using `PAT_TOKEN`.
3. Syncs the docs folder into `<target-directory>/` using `rsync --delete`.
4. Commits and pushes the changes — skips the commit if nothing changed.
5. **Dispatches a `repository_dispatch` event** (`docs-updated`) to the target repo with the following payload:
   - `repo` — full name of the calling repo (`owner/repo`)
   - `ref` — branch/tag that triggered the sync
   - `sha` — commit SHA at time of sync
   - `docs_directory` — path to the docs folder that was synced
6. The central repo rebuilds and redeploys from the `docs-updated` dispatch (or the `push` to `main` that the sync commit creates).

## Notes

- The `rsync --delete` flag mirrors the source exactly — files removed from `docs/` will also be removed in the central repo.
- `PAT_TOKEN` must have `contents:write` (fine-grained) or `repo` (classic) scope on `target-repo`.
- The `docs-updated` dispatch is only sent when files actually changed; no-op syncs are skipped entirely.
- Pair this workflow with a Pages-deploy workflow in the central repo triggered on `push` to `main` and `repository_dispatch: types: [docs-updated]`.
