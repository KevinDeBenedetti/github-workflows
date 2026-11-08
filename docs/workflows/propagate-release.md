---
title: '`propagate-release` workflow'
---

# `propagate-release` workflow

Moves the repositories that use this one to a new release as soon as it is published:
in each consumer repository, a pull request moves the pins of this repository's
workflows and actions to the release, and merges itself once its checks pass. Nothing
waits for a weekly Dependabot or Renovate run.

This repository calls it from [`ci-cd`](./ci-cd.md) after every release. Another
repository that publishes workflows or actions can call it the same way: the pins that
move are always those of the calling repository.

## Usage

```yaml
jobs:
  release:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/release.yml@main
    permissions:
      contents: write
      issues: write
      pull-requests: write

  propagate:
    needs: [release]
    if: needs.release.outputs.released == 'true' && needs.release.outputs.prerelease != 'true'
    uses: KevinDeBenedetti/github-workflows/.github/workflows/propagate-release.yml@main
    permissions:
      contents: read
    with:
      tag: ${{ needs.release.outputs.tag }}
      repositories: ${{ vars.PROPAGATE_REPOSITORIES }}
      app-client-id: ${{ vars.RELEASE_APP_CLIENT_ID }}
    secrets:
      APP_PRIVATE_KEY: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}
```

## Set up

1. A GitHub App with **Contents**, **Pull requests** and **Workflows** set to *Read and
   write*, installed on every consumer repository. A `GITHUB_TOKEN` can neither reach
   another repository nor change a workflow file.
2. In the repository that releases, the App's client ID as a variable, its private key
   as a secret, and the consumers as a variable, one per line:

   ```text
   web-app:dev
   api
   docs-site
   ```

   Each line is `name`, a repository of the same owner, or `name:branch` to target a
   branch other than the default one, such as an integration branch.
3. In each consumer repository:
   - for pull requests that merge themselves, allow auto-merge (**Settings → General →
     Allow auto-merge**) and require status checks on the target branch, in a ruleset:
     auto-merge waits for them. Without both, the pull request stays open for a person,
     so nothing merges before CI has run. On GitHub Free, a private repository has
     neither auto-merge nor rulesets: its pull requests always wait for a person;
   - when it runs [`check-bot-commits`](./check-bot-commits.md), add the App's bot,
     `<app-slug>[bot]`, to `allowed-bots`;
   - stop Dependabot or Renovate from proposing the same update. Dependabot, in its
     `github-actions` block:

     ```yaml
     ignore:
       - dependency-name: "KevinDeBenedetti/github-workflows*"
     ```

     Renovate: a `packageRules` entry with
     `"matchPackageNames": ["KevinDeBenedetti/github-workflows"], "enabled": false`.
4. Check the setup with a dry run: here, **Actions → Propagate release (manual) → Run
   workflow**; elsewhere, a call with `dry-run: true`. The log lists, for each
   repository, the pins that would move, and fails on any repository the App cannot
   reach.

## What moves

Only the `.yml` and `.yaml` files under `.github/` are read: workflows and composite
actions.

| Pin in the consumer                        | Result                                                               |
| ------------------------------------------ | -------------------------------------------------------------------- |
| `…@<commit SHA> # v1.2.3`                  | `…@<release SHA> # <tag>`                                            |
| `…@v1.2.3`                                 | `…@<tag>`                                                            |
| `…@main`, `…@v1`, `…@v1.2`                 | unchanged: a moving reference was chosen to follow a branch or alias |
| `…@<commit SHA>` without a version comment | unchanged: its release is unknown, as Dependabot reads it            |
| the release itself, or a newer one         | unchanged: never a downgrade                                         |

## The pull request

- One commit, made through the API so GitHub signs it, on the branch
  `bump/<repository name>`, based on the tip of the target branch, titled
  `ci(deps): bump <owner>/<name> to <tag>`. Its body lists each pin moved and links
  the release.
- The next release force-updates the same branch and pull request: a commit pushed to
  that branch is overwritten then.
- Auto-merge is turned on with the first merge method that both the repository and the
  rules of the target branch allow: squash, merge, rebase. When the repository does not
  allow auto-merge, or its branch requires no status check, the job says so in a
  notice and the pull request waits for a person; any other refusal is a warning.
- An archived repository is skipped. A repository that fails, for instance one the App
  is not installed on, is reported; the others still get their pull request, and the
  job fails at the end.

## Inputs

| Input           | Type    | Default             | Description                                                             |
| --------------- | ------- | ------------------- | ----------------------------------------------------------------------- |
| `repositories`  | string  | required            | Consumer repositories, one per line or comma-separated: `name[:branch]` |
| `tag`           | string  | `''`                | Release to move to; empty means the latest release                      |
| `app-client-id` | string  | required            | Client ID of the GitHub App                                             |
| `auto-merge`    | boolean | `true`              | Turn on auto-merge on each pull request                                 |
| `dry-run`       | boolean | `false`             | Log what would move, write nothing                                      |
| `runner`        | string  | `'"ubuntu-26.04"'`  | Runner labels as JSON; Linux with bash, curl, jq and python3            |

## Secrets

| Secret            | Required | Description                   |
| ----------------- | -------- | ----------------------------- |
| `APP_PRIVATE_KEY` | yes      | Private key of the GitHub App |

## Permissions

- The calling job grants `contents: read`, to read the release.
- Everything written in the consumer repositories goes through the App: its token is
  created for the listed repositories only, with `contents`, `pull-requests` and
  `workflows` write (read only, without `workflows`, in a dry run), and expires with
  the job.

## Notes

- A pull request opened with the App's token starts the consumer's workflows, unlike
  one opened with a `GITHUB_TOKEN`.
- One run at a time per repository: two releases in a row update the same pull
  requests one after the other.
- The [`propagate-release` action](../actions/propagate-release.md) does the work.
