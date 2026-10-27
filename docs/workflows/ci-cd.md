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
- Top-level `permissions: {}` (deny-all): each job grants only what it needs, and a reusable workflow never gets more than its caller job grants.

## Jobs

| Job              | Runs when      | Calls                            | Purpose                                                                                     |
| ---------------- | -------------- | -------------------------------- | ------------------------------------------------------------------------------------------- |
| `ci-shell`       | push + PR      | `ci-shell.yml`                   | ShellCheck, actionlint, Bats and docs checks, with the actions of this commit               |
| `ci-actions`     | push + PR      | `./.github/actions/*`            | Same checks with this checkout's actions, plus the locked ansible tools and Claude Code     |
| `ci-zizmor`      | push + PR      | `zizmorcore/zizmor-action`       | GitHub Actions security lint, pedantic persona                                              |
| `ci-prek`        | push + PR      | `ci-prek.yml`                    | This repo's prek hooks                                                                      |
| `security`       | push + PR      | `security.yml`                   | Gitleaks, dependency review and CodeQL (`actions`, `python`)                                |
| `ci-commits`     | push + PR      | `check-commit-msg` action        | Conventional Commits on every new commit                                                    |
| `ci-gate`        | push + PR      | —                                | The ruleset's single required check: every job above succeeded                              |
| `pr-description` | PR             | `./…/pr-description.yml` (local) | Pull request description written by Claude Code, outside the gate                           |
| `release`        | push to `main` | `./…/release.yml` (local)        | release-please PR, tags and `v0.<minor>` alias, once `ci-gate` passed                       |

## Notes

- The CI jobs also run on the release-please PR and on the `chore(main): release` commit: the reusable workflows reach their actions with `uses: $/…`, so nothing points at a tag that does not exist yet. A PR opened by `GITHUB_TOKEN` waits for "Approve workflows to run".
- `pr-description` is not in `ci-gate`'s needs: a missing `CLAUDE_CODE_OAUTH_TOKEN` secret or a model error never blocks a merge.
- `release` uses a local ref: GitHub validates `with:` inputs against the referenced workflow at parse time, so a remote `@main` ref would reject inputs a branch adds to `release.yml` before they are merged.
- Docs are not pushed anywhere: the central docs site polls this repo on a schedule (see [`cd-docs.md`](./cd-docs.md)). `ci-shell` verifies them.
