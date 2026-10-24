# Release

Automates releases using [release-please](https://github.com/googleapis/release-please-action).
Opens release PRs, creates GitHub Releases, and keeps the `v<major>` tag alias in sync.

## Usage

```yaml
jobs:
  release:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/release.yml@main
    with:
      config-file: release-please-config.json
      manifest-file: .release-please-manifest.json
      git-user-name: ${{ secrets.GITHUB_USERNAME }}
      git-user-email: ${{ secrets.GITHUB_EMAIL }}
    permissions:
      contents: write
      issues: write
      pull-requests: write
```

## Inputs

| Input             | Type   | Default            | Description                                                                                                                           |
| ----------------- | ------ | ------------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| `release-type`    | string | `''`               | release-please release type (e.g. `node`, `python`, `simple`). Ignored when `config-file` is provided.                              |
| `initial-version` | string | `'1.0.0'`          | Initial version for new releases (e.g. `0.1.0`, `1.0.0`). Only used if the manifest file doesn't exist.                             |
| `config-file`     | string | `''`               | Path to `release-please-config.json`. If empty, checks `.github/release/release-please-config.json` then `release-please-config.json`. |
| `manifest-file`   | string | `''`               | Path to `.release-please-manifest.json`. If empty, checks `.github/release/.release-please-manifest.json` then `.release-please-manifest.json`. |
| `git-user-name`   | string | `''`               | Name for the git tagger identity when moving the major version tag. Falls back to the `GIT_USER_NAME` repo variable, then `github-actions[bot]`. |
| `git-user-email`  | string | `''`               | Email for the git tagger identity when moving the major version tag. Falls back to the `GIT_USER_EMAIL` repo variable, then the Actions noreply address. |
| `runner`          | string | `'"ubuntu-latest"'` | Runner labels as JSON — e.g. `'"ubuntu-latest"'` or `'["self-hosted","linux","k3s","kaniko"]'`.                                     |
| `notify-reviewers`| string | `''`               | Comma-separated GitHub usernames to notify when a release PR is opened. Each user is requested as a reviewer **and** @mentioned in a PR comment, so a notification reliably reaches them. Each PR is notified at most once. Leave empty to disable. |
| `release-pending-label` | string | `'autorelease: pending'` | Label used to find the open release PR on runs where release-please didn't create/update it (the fallback path for `notify-reviewers`). Override only if you customized `pull-request-label` in your release-please config. |
| `pre-major-alias` | string | `both`             | Alias tag(s) moved while at 0.x: `both` (`v0` + `v0.<minor>`), `minor` (`v0.<minor>` only) or `major` (`v0` only). Ignored from 1.0. |
| `app-client-id`   | string | `''`               | **Deprecated, ignored** (a warning is printed): the release runs on `GITHUB_TOKEN`. Still declared so existing callers don't fail. |
| `app-workflows-permission` | boolean | `false` | **Deprecated, ignored.** |

## Secrets

| Secret            | Required | Description                                                                          |
| ----------------- | -------- | ------------------------------------------------------------------------------------ |
| `RELEASE_TOKEN`   | no       | **Deprecated, ignored** (a warning is printed): the release runs on `GITHUB_TOKEN`. |
| `APP_PRIVATE_KEY` | no       | **Deprecated, ignored.** |

## Outputs

| Output     | Description                              |
| ---------- | ---------------------------------------- |
| `released` | `'true'` if a GitHub Release was created |
| `tag`      | Tag name of the release (e.g. `v1.2.3`)  |

## Jobs

| Job             | Description                                               |
| --------------- | --------------------------------------------------------- |
| `release`       | Runs release-please; creates release PR or GitHub Release |
| `tag-workflows` | Moves the `v<major>` alias tag (before 1.0: `v0` and/or `v0.<minor>`, per `pre-major-alias`) after each release |

## Notes

- The `tag-workflows` job only runs when `released == 'true'`.
- The major alias (e.g. `v1`) is force-pushed after each release, enabling callers to pin to `@v1` without a breaking update.
- Before 1.0, `pre-major-alias` picks the alias(es): `both` (default) moves `v0` and `v0.<minor>` (e.g. `v0.25`); `minor` moves only `v0.<minor>` — with `bump-minor-pre-major`, release-please ships breaking changes as minor bumps, so a moving `v0` carries callers across them; `major` moves only `v0`. Switching to `minor` freezes an existing `v0` tag: tell callers pinned to `@v0` to move to `@v0.<minor>`.
- When using a monorepo, prefer `config-file` + `manifest-file` over `release-type`.
- With `notify-reviewers` set, the PR comment carries a hidden `<!-- release-please-notify -->` marker. Both the review request and the comment are gated on this marker, so once a PR is notified, later runs (on any push while the PR stays open) skip it entirely — reviewers are never re-requested or re-pinged.
- Notification also fires on release PRs that release-please left untouched this run (e.g. `notify-reviewers` was added after the PR opened): the workflow falls back to finding the open PR by `release-pending-label`.
- A review request alone can be missed (it depends on each user's notification settings), which is why an @mention comment is also posted — mentions notify reliably. This matters when the release PR is opened by a bot or another account rather than by you.

## Token: `GITHUB_TOKEN` only

The release runs on the job's `GITHUB_TOKEN` — no PAT or GitHub App to create, store or rotate. The calling job grants it `contents`, `issues` and `pull-requests: write` (see Usage). What that implies:

- **Repository setting**: enable *Settings → Actions → General → Allow GitHub Actions to create and approve pull requests*, or release-please cannot open the release PR. An approval by `github-actions[bot]` does not count as a Code Owner review.
- **CI on the release PR waits for approval**: a PR opened by `GITHUB_TOKEN` creates its `pull_request` runs in an *approval-required* state — a user with write access starts them with **Approve workflows to run** on the PR. Other events created by `GITHUB_TOKEN` start no workflow at all.
- **No workflow files in `extra-files`**: `GITHUB_TOKEN` can never update `.github/workflows/` (release-please fails with `Error adding to tree`). This repository does not need it: its workflows reach their own actions with `uses: $/…`, resolved to the commit they run from, so nothing there carries a version to bump.
- **No workflows triggered by the release itself**: tags and releases created with `GITHUB_TOKEN` don't fire `on: release` / `on: push: tags` workflows.
- Release commits are authored by `github-actions[bot]`: if you run `check-bot-commits` on release PRs, allow that login.

`app-client-id`, `app-workflows-permission`, `APP_PRIVATE_KEY` and `RELEASE_TOKEN` were supported until this change. They are still accepted and ignored with a warning: drop them from the caller, then delete the matching repository variables and secrets.
