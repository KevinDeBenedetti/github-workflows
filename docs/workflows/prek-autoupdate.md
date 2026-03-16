# prek Autoupdate

Runs `prek autoupdate` to bump all hook revisions in `prek.toml` to their latest versions, then opens a pull request with the changes via [`peter-evans/create-pull-request`](https://github.com/peter-evans/create-pull-request).

## Usage

```yaml
jobs:
  autoupdate:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/prek-autoupdate.yml@main
    secrets: inherit
```

## Inputs

| Input       | Type   | Default                 | Description                                                                 |
| ----------- | ------ | ----------------------- | --------------------------------------------------------------------------- |
| `branch`    | string | `chore/prek-autoupdate` | Branch name for the autoupdate PR                                           |
| `labels`    | string | `''`                    | Comma-separated labels to add to the PR (e.g. `dependencies,chore`)        |
| `git-name`  | string | `''`                    | Git committer name — falls back to `GIT_USER_NAME` variable, then `github-actions[bot]` |
| `git-email` | string | `''`                    | Git committer email — falls back to `GIT_USER_EMAIL` variable, then the Actions noreply address |

## Secrets

| Secret      | Required | Description                                                                     |
| ----------- | -------- | ------------------------------------------------------------------------------- |
| `PAT_TOKEN` | ✅        | Personal Access Token with `contents:write` and `pull-requests:write` scopes   |

## Schedule

This workflow also fires automatically every Monday at 06:00 UTC via a built-in `schedule` trigger:

```yaml
on:
  schedule:
    - cron: '0 6 * * 1'
  workflow_dispatch:

jobs:
  autoupdate:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/prek-autoupdate.yml@main
    secrets: inherit
```

## Notes

- Requires [prek](https://prek.j178.dev) configuration in `prek.toml`.
- If `prek autoupdate` produces no changes, no PR is opened.
- The committer identity on the resulting commit can be customized via `git-name` / `git-email` inputs or via repository variables `GIT_USER_NAME` / `GIT_USER_EMAIL`.
