---
title: Action — notify-release-reviewers
---

# Action — notify-release-reviewers

Requests a review on the open release PR from each listed user who was never asked to review it, so each gets one GitHub notification per release PR, with no `@mention` comment on top. [`release`](../workflows/release.md) runs it after release-please when `notify-reviewers` is set.

## Usage

```yaml
steps:
  - id: rp
    uses: googleapis/release-please-action@v5

  - uses: KevinDeBenedetti/github-workflows/.github/actions/notify-release-reviewers@main
    with:
      reviewers: octocat,hubot
      prs: ${{ steps.rp.outputs.prs }}
      base-branch: main
```

The job needs `pull-requests: write`.

## Inputs

| Input           | Default                  | Description                                                              |
| --------------- | ------------------------ | ------------------------------------------------------------------------ |
| `reviewers`     | —                        | Comma-separated GitHub logins                                            |
| `prs`           | `''`                     | release-please's `prs` output; empty looks the PR up by `pending-label`  |
| `pending-label` | `'autorelease: pending'` | release-please's pending label                                           |
| `base-branch`   | `''`                     | Base branch of the release PR; empty matches any                         |
| `token`         | job token                | Requests the reviews and reads the PR timeline                           |

## Notes

- The PRs: those in `prs` when release-please created or updated one this run, otherwise the open PRs with `pending-label` on `base-branch`. An untouched release PR may still need its first notification, when `reviewers` was added after it opened or an earlier attempt failed.
- A user is asked only when the PR's timeline has no `review_requested` event for that login, whatever its case: from an earlier run, or from GitHub through CODEOWNERS. A user who has reviewed or was removed since is not asked again.
- Never fails the step: a value that is not a login, a failed PR list, an unreadable timeline or a refused request is a `::warning::` with GitHub's answer, and the other PRs and users go on. In `release`, a failed step would keep the alias tags from moving.
