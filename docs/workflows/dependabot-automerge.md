# `dependabot-automerge` workflow

Automatically approves and merges Dependabot PRs for **minor** and **patch** updates using a personal account token (no bot identity in commits). **Major** updates are labelled for manual review and left open.

## Usage

```yaml
# .github/workflows/dependabot.yml  (in your repo)
name: Dependabot

on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]

jobs:
  automerge:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/dependabot-automerge.yml@main
    secrets: inherit
```

> **Required secret:** add `PAT_TOKEN` to your repository (or organisation) secrets. It must be a Personal Access Token belonging to a human account — this ensures no bot identity appears in merge commits.

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `merge-method` | string | `squash` | Merge strategy: `squash`, `merge`, or `rebase` |
| `major-label` | string | `major-update` | Label applied to major-version PRs for manual review |

## Secrets

| Secret | Required | Description |
|---|---|---|
| `PAT_TOKEN` | **yes** | Personal Access Token used to approve and merge PRs |

## Behaviour

| Update type | Action |
|---|---|
| `semver-patch` | Approve PR + enable auto-merge (waits for required checks to pass) |
| `semver-minor` | Approve PR + enable auto-merge (waits for required checks to pass) |
| `semver-major` | Apply `major-update` label + post comment — **no auto-merge** |

The workflow only runs when `github.actor == 'dependabot[bot]'`, so it is a no-op on all other PRs.

## Notes

- **Branch protection required:** `--auto` merge only takes effect if your repository has branch protection with at least one required status check. Without it the PR is merged immediately after approval.
- **Squash merge** (default) keeps your commit history clean — the merge commit is attributed to the PAT owner (your personal account), not dependabot.
- To enable auto-merge in your repository settings: **Settings → General → Allow auto-merge**.
