# CI / CD (orchestrator)

The repository's **own** top-level pipeline. Unlike the other docs here, this is **not** a reusable
`workflow_call` workflow — it is the caller that wires the reusable workflows together on pushes to
the default branch. Use it as a reference example for composing the building blocks in your own repo.

## Triggers

```yaml
on:
  push:
    branches: [main, develop]
```

- `concurrency` is keyed on <code v-pre>${{ github.workflow }}-${{ github.ref }}</code> with `cancel-in-progress: true`, so a new push supersedes an in-flight run on the same ref.
- No top-level `permissions` block — jobs inherit the repository's default token permissions. Each reusable workflow declares its own job-level permissions, capped by what the caller grants.

## Jobs

| Job           | Runs when      | Calls          | Purpose                                                       |
| ------------- | -------------- | -------------- | ------------------------------------------------------------- |
| `release`     | push to `main` | `release.yml`  | Runs release-please to cut releases. Uses `secrets: inherit`. |
| `deploy-docs` | push to `main` | `cd-docs.yml`  | Dispatches `docs-updated` to the central docs site.           |

### `deploy-docs` wiring

```yaml
deploy-docs:
  uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-docs.yml@main
  with:
    client-id: ${{ vars.DOCS_APP_CLIENT_ID }}
  secrets:
    APP_PRIVATE_KEY: ${{ secrets.DOCS_APP_PRIVATE_KEY }}
```

## Notes

- `release` and `deploy-docs` are gated on `github.event_name == 'push' && github.ref == 'refs/heads/main'`, so they never run on `develop` pushes.
- `release` uses `secrets: inherit` to forward the repository secrets to `release.yml`; `deploy-docs` passes the docs App private key explicitly.
- See [`cd-docs.md`](./cd-docs.md) for the docs sync workflow's full inputs and secrets.
- The [`check-bot-commits`](./check-bot-commits.md) reusable workflow is still available for other repos, but is not wired into this pipeline (the only bots opening PRs here are trusted automation).
