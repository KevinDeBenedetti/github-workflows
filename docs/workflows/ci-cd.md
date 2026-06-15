# CI / CD (orchestrator)

The repository's **own** top-level pipeline. Unlike the other docs here, this is **not** a reusable
`workflow_call` workflow — it is the caller that wires the reusable workflows together on push and
pull-request events. Use it as a reference example for composing the building blocks in your own repo.

## Triggers

```yaml
on:
  push:
    branches: [main, develop]
  pull_request:
    types: [opened, synchronize]
```

- `concurrency` is keyed on <code v-pre>${{ github.workflow }}-${{ github.ref }}</code> with `cancel-in-progress: true`, so a new push supersedes an in-flight run on the same ref.
- Top-level `permissions: {}` — the orchestrator grants nothing itself; each reusable workflow declares its own job-level permissions.

## Jobs

| Job                 | Runs when                                | Calls                  | Purpose                                                            |
| ------------------- | ---------------------------------------- | ---------------------- | ----------------------------------------------------------------- |
| `release`           | push to `main`                           | `release.yml`          | Runs release-please to cut releases. Uses `secrets: inherit`.     |
| `deploy-docs`       | push to `main`                           | `cd-docs.yml`          | Dispatches `docs-updated` to the central docs site.               |
| `check-bot-commits` | `pull_request` events                    | `check-bot-commits.yml`| Verifies PR commits come only from allowed bots.                  |

### `deploy-docs` wiring

```yaml
deploy-docs:
  uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-docs.yml@main
  with:
    client-id: ${{ vars.DOCS_APP_CLIENT_ID }}
  secrets:
    APP_PRIVATE_KEY: ${{ secrets.DOCS_APP_PRIVATE_KEY }}
```

### `check-bot-commits` wiring

```yaml
check-bot-commits:
  uses: KevinDeBenedetti/github-workflows/.github/workflows/check-bot-commits.yml@main
  with:
    allowed-bots: '["dependabot[bot]"]'
```

## Notes

- `release` and `deploy-docs` are gated on `github.event_name == 'push' && github.ref == 'refs/heads/main'`, so they never run on `develop` pushes or pull requests.
- `check-bot-commits` runs only on `pull_request` events.
- `release` uses `secrets: inherit` to forward the repository secrets to `release.yml`; `deploy-docs` passes the docs App private key explicitly.
- See [`cd-docs.md`](./cd-docs.md) for the docs sync workflow's full inputs and secrets.
