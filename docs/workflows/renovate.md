# `renovate` workflow

Runs [Renovate](https://docs.renovatebot.com/) to keep dependencies up to date. All pull requests are opened **by your personal GitHub account** (via `PAT_TOKEN`) — no bot identity in your contributor list.

Replaces native GitHub Dependabot version-update PRs. Dependabot security alerts remain active via repository settings independently.

## Usage

**1. Add the caller workflow** (copy [`examples/renovate.yml`](../../examples/renovate.yml)):

```yaml
# .github/workflows/renovate.yml  (in your repo)
name: Renovate

on:
  schedule:
    - cron: '0 3 * * 1'  # Every Monday at 03:00 UTC
  workflow_dispatch:

jobs:
  renovate:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/renovate.yml@main
    secrets: inherit
```

**2. Add a `renovate.json`** to your repo root to extend the shared base config:

```json
{
  "$schema": "https://docs.renovatebot.com/configuration-options.json",
  "extends": ["github>KevinDeBenedetti/github-workflows"]
}
```

This pulls in the [`default.json`](../../default.json) preset: grouped minor/patch PRs, `major-update` label on majors, auto-assigned to `KevinDeBenedetti`.

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `configuration-file` | string | `''` | Path to Renovate config (auto-discovered if empty) |

## Secrets

| Secret | Required | Description |
|---|---|---|
| `PAT_TOKEN` | **yes** | Personal Access Token — PRs are opened as this user |

## PAT scopes required

Fine-grained PAT (recommended):
- **Contents**: Read and write
- **Pull requests**: Read and write
- **Workflows**: Read and write (needed to update workflow files)

## Behaviour

| Update type | Result |
|---|---|
| minor / patch | Single grouped PR — `dependencies` label |
| major | Individual PR — `dependencies` + `major-update` labels |

Combine with [`dependabot-automerge.yml`](./dependabot-automerge.md) to auto-merge minor/patch PRs after CI passes.

## Notes

- The git author identity is hardcoded to `Kevin De Benedetti <contact@kevindb.dev>` so commits inside Renovate PRs match the personal account.
- The shared preset (`default.json`) is versioned in this repo — pin callers to a SHA in production.
- To disable Renovate for specific packages, add `packageRules` in your `renovate.json` extending the base.
