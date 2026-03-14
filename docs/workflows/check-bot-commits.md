# `check-bot-commits` workflow

Guards pull requests against commits authored by bot accounts. Any commit whose author login ends with `[bot]` (GitHub's convention) fails the check unless that bot is explicitly allow-listed.

## Usage

```yaml
# .github/workflows/pr-checks.yml  (in your repo)
name: PR Checks

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  bot-guard:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/check-bot-commits.yml@main
```

### Allow-listing specific bots

```yaml
jobs:
  bot-guard:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/check-bot-commits.yml@main
    with:
      allowed-bots: '["dependabot[bot]"]'
```

### Warn instead of fail

```yaml
jobs:
  bot-guard:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/check-bot-commits.yml@main
    with:
      fail-on-bot-commits: false
```

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `allowed-bots` | string | `'[]'` | JSON array of bot logins whose commits are permitted |
| `fail-on-bot-commits` | boolean | `true` | Fail the job when bot commits are found (false = warning only) |

## Behaviour

The workflow:
1. Lists all commits in the PR via the GitHub API
2. Checks each commit's author login for the `[bot]` suffix
3. Passes if no bot authors are found (or all found bots are in `allowed-bots`)
4. Fails (or warns) otherwise, printing each unauthorised bot author

## Notes

- The check is skipped on non-PR events (push, workflow_dispatch, etc.).
- Dependabot PRs are handled separately by `dependabot-automerge.yml`; if you use both workflows together, add `dependabot[bot]` to `allowed-bots` on the bot-guard job or scope the bot-guard trigger to exclude dependabot.
- Bot commits that have already landed on the default branch are not checked — this only covers incoming PR commits.
