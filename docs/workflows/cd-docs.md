# Deploy — Docs to Central Repo

Verifies a repo's `docs/` before the centralized docs site
(`KevinDeBenedetti/kevindebenedetti.github.io`) picks them up.

The central site is **pull-based**: its `docs-poll.yml` workflow compares the `docs/` tree SHA of
every public repo with the state the live site was built from (every 12 hours, or on demand) and
rebuilds when something changed. Its `sync-docs.ts` then re-clones the latest `docs/` from every
public repo. Source repos therefore need no token, App or secret: this workflow only makes sure
the docs are valid before they are published.

## Usage

```yaml
jobs:
  docs:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-docs.yml@main
```

## Inputs

| Input              | Type   | Default                                         | Description                                                                        |
| ------------------ | ------ | ----------------------------------------------- | ---------------------------------------------------------------------------------- |
| `docs-directory`   | string | `docs`                                          | Docs folder in the calling repo, verified by the `verify` job                       |
| `client-id`        | string | `''`                                            | **Deprecated, leave empty.** When set, the legacy `docs-updated` dispatch is also sent (see below) |
| `target-repo`      | string | `KevinDeBenedetti/kevindebenedetti.github.io`   | Legacy dispatch only: repository that receives the event                            |
| `target-directory` | string | _(calling repo name)_                           | Legacy dispatch only: logical name sent in the payload                              |

## Outputs

| Output        | Description                                                                 |
| ------------- | --------------------------------------------------------------------------- |
| `docs-synced` | `"true"` when the legacy `docs-updated` event was dispatched; empty otherwise |

## Secrets

| Secret            | Required | Description                                             |
| ----------------- | -------- | ------------------------------------------------------- |
| `APP_PRIVATE_KEY` | ❌        | Legacy dispatch only: private key of the `client-id` App |

## How it works

1. A `verify` job checks out the calling repo and runs
   [`check-docs-links`](../actions/check-docs-links.md) and
   [`check-vitepress-md`](../actions/check-vitepress-md.md) against `docs-directory`
   (default `docs`), so a broken doc fails the caller's CI instead of the central build.
2. The central site's scheduled poll notices the new `docs/` tree SHA and rebuilds.

## Migrating from the dispatch

Callers that still pass `client-id` / `APP_PRIVATE_KEY` keep working: the `dispatch` job
then mints an App token and sends the old `repository_dispatch` event. To drop the App, remove
both from the caller, then delete the `DOCS_APP_CLIENT_ID` variable and `DOCS_APP_PRIVATE_KEY`
secret:

```diff
   docs:
     uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-docs.yml@main
-    with:
-      client-id: ${{ vars.DOCS_APP_CLIENT_ID }}
-    secrets:
-      APP_PRIVATE_KEY: ${{ secrets.DOCS_APP_PRIVATE_KEY }}
```
