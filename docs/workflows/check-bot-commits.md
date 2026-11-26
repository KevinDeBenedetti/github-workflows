---
title: Check Bot Commits
---

# Check Bot Commits

Guards pull requests against commits authored by bot accounts. A bot commit fails the
check unless the bot's account login is allow-listed. The job is the
[`check-bot-commits`](../actions/check-bot-commits.md) action, whose page holds the rules.

## Usage

```yaml
# .github/workflows/pr-checks.yml  (in your repo)
name: PR Checks

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  bot-guard:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/check-bot-commits.yml@v0.57.0 # x-release-please-version
```

### Allow-listing specific bots

```yaml
jobs:
  bot-guard:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/check-bot-commits.yml@v0.57.0 # x-release-please-version
    with:
      allowed-bots: '["dependabot[bot]"]'
```

### Warn instead of fail

```yaml
jobs:
  bot-guard:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/check-bot-commits.yml@v0.57.0 # x-release-please-version
    with:
      fail-on-bot-commits: false
```

## Inputs

| Input                 | Type    | Default            | Description                                                                                                 |
| --------------------- | ------- | ------------------ | ----------------------------------------------------------------------------------------------------------- |
| `allowed-bots`        | string  | `'[]'`             | JSON array of bot account logins whose commits are permitted                                                |
| `fail-on-bot-commits` | boolean | `true`             | Fail the job when bot commits are found (false = warning only)                                              |
| `runner`              | string  | `'"ubuntu-26.04"'` | Runner labels as JSON — e.g. `'"ubuntu-26.04"'` or `'"ubicloud-standard-2"'` |

## Behaviour

1. Lists every commit of the pull request through the GitHub API
2. Flags a commit as a bot's by its account type, its login, its no-reply e-mail, or, for a commit linked to no account, its author name
3. Passes when no bot commit is found, or when each one is linked to an account in `allowed-bots`
4. Fails (or warns) otherwise, listing each blocked commit in the log and the job summary

## Notes

- The job runs on `pull_request` and `pull_request_target` events only.
- It fails closed: an API error, or a pull request with more than the 250 commits GitHub lists, fails the job even with `fail-on-bot-commits: false`.
- `allowed-bots` matches account logins only: a commit whose author name is `renovate[bot]` but that is linked to no account stays blocked.
- To allow a bot's commits, add it to `allowed-bots` — e.g. `dependabot[bot]` or `github-actions[bot]` for release-please PRs.
- Bot commits that have already landed on the default branch are not checked — this only covers incoming PR commits.
- Needs runner 2.336.0 or newer: the workflow calls the action with `uses: $/…`.
