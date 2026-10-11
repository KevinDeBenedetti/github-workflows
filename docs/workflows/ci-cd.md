# CI / CD (orchestrator)

The repository's **own** top-level pipeline. Unlike the other docs here, this is **not** a reusable
`workflow_call` workflow — it is the caller that wires the reusable workflows together on pushes to
the default branch. Use it as a reference example for composing the building blocks in your own repo.

## Triggers

```yaml
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]
  workflow_dispatch:
```

- `concurrency` is keyed on <code v-pre>${{ github.workflow }}-${{ github.ref }}</code>; only pull-request runs are cancelled by a newer push, so an in-flight release on `main` always finishes.
- No top-level `permissions` block — jobs inherit the repository's default token permissions. Each reusable workflow declares its own job-level permissions, capped by what the caller grants.

## Jobs

| Job          | Runs when      | Calls                     | Purpose                                                                 |
| ------------ | -------------- | ------------------------- | ----------------------------------------------------------------------- |
| `ci-shell`   | push + PR      | `ci-shell.yml`            | ShellCheck, actionlint, Bats and docs checks, with the released actions |
| `ci-actions` | push + PR      | `./.github/actions/*`     | Same checks through this checkout's own composite actions               |
| `ci-prek`    | push + PR      | `ci-prek.yml`             | This repo's prek hooks                                                  |
| `security`   | push + PR      | `security.yml`            | Gitleaks secret scan                                                    |
| `release`    | push to `main` | `./…/release.yml` (local) | release-please PR, tags and `v0.<minor>` alias, once CI is green        |

## Notes

- The CI jobs are skipped on the release-please PR and on the `chore(main): release` commit; `release` still runs (skipped ≠ failed).
- `release` uses a local ref: GitHub validates `with:` inputs against the referenced workflow at parse time, so a remote `@main` ref would reject inputs a branch adds to `release.yml` before they are merged.
- Docs are not pushed anywhere: the central docs site polls this repo on a schedule (see [`cd-docs.md`](./cd-docs.md)). `ci-shell` verifies them.
