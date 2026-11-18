---
title: Action — check-bot-commits
---

# Action — check-bot-commits

Fails a pull request that brings commits authored by a bot account, unless the bot's
account login is allow-listed. The [`check-bot-commits`](../workflows/check-bot-commits.md)
workflow runs it; use the action directly to add the guard to a job of your own. It
needs bash, curl and jq, and no checkout.

## Usage

```yaml
on: pull_request

jobs:
  bot-guard:
    runs-on: ubuntu-26.04
    permissions:
      pull-requests: read
    steps:
      - uses: KevinDeBenedetti/github-workflows/.github/actions/check-bot-commits@main
        with:
          allowed-bots: '["dependabot[bot]"]'
```

## Inputs

| Input                 | Default                                | Description                                                |
| --------------------- | -------------------------------------- | ---------------------------------------------------------- |
| `allowed-bots`        | `'[]'`                                 | JSON array of bot account logins whose commits are allowed |
| `fail-on-bot-commits` | `'true'`                               | `'false'` warns instead of failing                         |
| `github-token`        | <code v-pre>${{ github.token }}</code> | Token with `pull-requests: read`                           |

## Outputs

| Output    | Description                                        |
| --------- | -------------------------------------------------- |
| `checked` | Commits checked                                    |
| `blocked` | Bot commits whose account is not in `allowed-bots` |

## Rules

A commit is a bot's when any of these holds:

- the GitHub account it is linked to has the type `Bot`;
- that account's login ends with `[bot]`;
- its author e-mail is a bot's no-reply address, `<id>+<name>[bot]@users.noreply.github.com`;
- it is linked to no account and its author name ends with `[bot]`.

A bot commit passes only when it is linked to an account listed in `allowed-bots`. A
commit's author name and e-mail are whatever its author wrote, so they can flag a
commit as a bot's, never allow one: a commit named `renovate[bot]` but linked to no
account is blocked even when `renovate[bot]` is allowed.

## Notes

- Fails closed, whatever `fail-on-bot-commits` says: an API error fails the step, and
  so does a pull request with more commits than GitHub lists (250 at most), rather
  than passing with commits unchecked.
- On any event other than a pull request, nothing is checked and the step passes with
  a notice.
- The job summary lists each commit, its author and its verdict. Author names and
  e-mails are written as plain text: no link, HTML or formatting from a commit
  reaches the summary.
- Locally, with `GITHUB_TOKEN`, `GITHUB_REPOSITORY` and `PR_NUMBER` set:
  `bash .github/actions/check-bot-commits/check-bot-commits.sh`.
