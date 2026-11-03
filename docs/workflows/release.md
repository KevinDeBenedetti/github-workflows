---
title: Release
---

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
| `target-branch`   | string | `''`               | Branch the release PR targets and releases are cut from, e.g. `dev` for [pre-releases from a second branch](#pre-releases-from-a-second-branch). Empty: the repository's default branch. |
| `git-user-name`   | string | `''`               | Name for the git tagger identity when moving the major version tag. Falls back to the `GIT_USER_NAME` repo variable, then `github-actions[bot]`. |
| `git-user-email`  | string | `''`               | Email for the git tagger identity when moving the major version tag. Falls back to the `GIT_USER_EMAIL` repo variable, then the Actions noreply address. |
| `runner`          | string | `'"ubuntu-latest"'` | Runner labels as JSON — e.g. `'"ubuntu-latest"'` or `'"my-scale-set"'` (the name of an ARC runner scale set).                                     |
| `notify-reviewers`| string | `''`               | Comma-separated GitHub usernames to request a review from when a release PR is opened, so each gets one GitHub notification. A user already asked to review that PR (by an earlier run, or by GitHub through CODEOWNERS) is skipped. Leave empty to disable. |
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
| `prerelease` | `'true'` if the release is a semver pre-release (e.g. `v1.3.0-rc.2`), which moves no alias tag |

## Jobs

| Job             | Description                                               |
| --------------- | --------------------------------------------------------- |
| `release`       | Runs release-please; creates release PR or GitHub Release |
| `tag-workflows` | Moves the `v<major>` alias tag (before 1.0: `v0` and/or `v0.<minor>`, per `pre-major-alias`) after each final release; skipped for a pre-release |

## Notes

- The `tag-workflows` job only runs when `released == 'true'` and `prerelease` is not: a pre-release (`v1.3.0-rc.2`) leaves `v1` on the last final release.
- The major alias (e.g. `v1`) is force-pushed after each release, enabling callers to pin to `@v1` without a breaking update.
- Before 1.0, `pre-major-alias` picks the alias(es): `both` (default) moves `v0` and `v0.<minor>` (e.g. `v0.25`); `minor` moves only `v0.<minor>` — with `bump-minor-pre-major`, release-please ships breaking changes as minor bumps, so a moving `v0` carries callers across them; `major` moves only `v0`. Switching to `minor` freezes an existing `v0` tag: tell callers pinned to `@v0` to move to `@v0.<minor>`.
- When using a monorepo, prefer `config-file` + `manifest-file` over `release-type`.
- With `notify-reviewers` set, a listed user is requested as a reviewer only when the PR's timeline has no `review_requested` event for them yet. Later runs (on any push while the PR stays open) skip users already asked, even once they have reviewed or been removed, so nobody is pinged twice.
- Notification also fires on release PRs that release-please left untouched this run (e.g. `notify-reviewers` was added after the PR opened): the workflow falls back to finding the open PR by `release-pending-label`.
- Only a review request is sent — no @mention comment — so each user gets a single notification per release PR. When a listed user owns the release PR's files through CODEOWNERS, GitHub requests their review itself as the PR opens, and the workflow leaves them alone.
- That fallback only looks at release PRs into `target-branch` (else the default branch): with a pre-release branch, both release PRs carry the pending label.

## Pre-releases from a second branch

To cut the pre-releases of a long-lived `dev` branch through a pull request, the way the default branch cuts its releases, call the workflow a second time, on pushes to `dev`, with its own config and manifest. For pre-releases tagged on every push without a pull request, see [prerelease.yml](./prerelease.md).

```yaml
jobs:
  release-dev:
    if: github.ref == 'refs/heads/dev' && github.event_name == 'push'
    uses: KevinDeBenedetti/github-workflows/.github/workflows/release.yml@main
    with:
      target-branch: dev
      config-file: .github/release/release-please-config.dev.json
      manifest-file: .github/release/.release-please-manifest.dev.json
    permissions:
      contents: write
      issues: write
      pull-requests: write
```

The dev config is the default branch's, with the pre-release settings:

```json
{
  "packages": {
    ".": {
      "release-type": "node",
      "versioning": "prerelease",
      "prerelease": true,
      "prerelease-type": "rc.1",
      "skip-changelog": true
    }
  }
}
```

- Each `feat`, `fix` or `perf` pushed to `dev` opens or updates the pull request `chore(dev): release 1.3.0-rc.1`. Merging it tags `v1.3.0-rc.1` and creates a GitHub pre-release, never marked latest: `released` and `prerelease` are `'true'`, and the alias tags stay on the last final release. A build or deploy job gated on `released`, as for the default branch, ships it.
- The next pre-releases count up, `rc.2`, `rc.3`, while the version stays the one the default branch would release next. `prerelease-type` is the suffix of the first one after a final version: `rc.1` gives `1.3.0-rc.1`, then `rc.2`; `rc` would give `1.3.0-rc`, then `rc.1`.
- `skip-changelog` leaves `CHANGELOG.md` to the final releases: the default branch's release PR covers every change since the last final one. The pre-release notes are still in the pull request and on the GitHub pre-release.
- Two manifests, never one. The default branch finds its last release through its manifest: holding a pre-release, it would cover only the commits since that pre-release, none once `dev` is merged.
- Keep the dev manifest in step with the finals: list it in the default branch config's `extra-files`, so each release PR also sets it to the version released, then merge the default branch into `dev`. Until that merge, `dev` still holds the last pre-release of a version that is out, and its next pull request would propose `v1.3.0-rc.4` after `v1.3.0`.

```json
"extra-files": [
  {
    "type": "json",
    "path": ".github/release/.release-please-manifest.dev.json",
    "jsonpath": "$['.']"
  }
]
```

## Token: `GITHUB_TOKEN` only

The release runs on the job's `GITHUB_TOKEN` — no PAT or GitHub App to create, store or rotate. The calling job grants it `contents`, `issues` and `pull-requests: write` (see Usage). What that implies:

- **Repository setting**: enable *Settings → Actions → General → Allow GitHub Actions to create and approve pull requests*, or release-please cannot open the release PR. An approval by `github-actions[bot]` does not count as a Code Owner review.
- **CI on the release PR waits for approval**: a PR opened by `GITHUB_TOKEN` creates its `pull_request` runs in an *approval-required* state — a user with write access starts them with **Approve workflows to run** on the PR. Other events created by `GITHUB_TOKEN` start no workflow at all.
- **No workflow files in `extra-files`**: `GITHUB_TOKEN` can never update `.github/workflows/` (release-please fails with `Error adding to tree`). This repository does not need it: its workflows reach their own actions with `uses: $/…`, resolved to the commit they run from, so nothing there carries a version to bump.
- **No workflows triggered by the release itself**: tags and releases created with `GITHUB_TOKEN` don't fire `on: release` / `on: push: tags` workflows.
- Release commits are authored by `github-actions[bot]`: if you run `check-bot-commits` on release PRs, allow that login.

`app-client-id`, `app-workflows-permission`, `APP_PRIVATE_KEY` and `RELEASE_TOKEN` were supported until this change. They are still accepted and ignored with a warning: drop them from the caller, then delete the matching repository variables and secrets.
