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
    secrets:
      RELEASE_TOKEN: ${{ secrets.RELEASE_TOKEN }}
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
| `app-client-id`   | string | `''`               | Client ID (or App ID) of a GitHub App with contents/pull-requests/issues write. When set, a short-lived App token is used instead of `GITHUB_TOKEN`, so the release PR is attributed to the App (avoids the workflow-approval gate and lets CI run on the release PR). |

## Secrets

| Secret            | Required | Description                                                                          |
| ----------------- | -------- | ------------------------------------------------------------------------------------ |
| `RELEASE_TOKEN`   | no       | PAT with `contents: write` and `pull-requests: write`. Falls back to `GITHUB_TOKEN`. |
| `APP_PRIVATE_KEY` | no       | Private key of the GitHub App referenced by `app-client-id`. Required when `app-client-id` is set. |

## Outputs

| Output     | Description                              |
| ---------- | ---------------------------------------- |
| `released` | `'true'` if a GitHub Release was created |
| `tag`      | Tag name of the release (e.g. `v1.2.3`)  |

## Jobs

| Job             | Description                                               |
| --------------- | --------------------------------------------------------- |
| `release`       | Runs release-please; creates release PR or GitHub Release |
| `tag-workflows` | Moves the `v<major>` alias tag after each release         |

## Notes

- The `tag-workflows` job only runs when `released == 'true'`.
- The major alias (e.g. `v1`) is force-pushed after each release, enabling callers to pin to `@v1` without a breaking update.
- When using a monorepo, prefer `config-file` + `manifest-file` over `release-type`.
- With `notify-reviewers` set, the PR comment carries a hidden `<!-- release-please-notify -->` marker. Both the review request and the comment are gated on this marker, so once a PR is notified, later runs (on any push while the PR stays open) skip it entirely — reviewers are never re-requested or re-pinged.
- Notification also fires on release PRs that release-please left untouched this run (e.g. `notify-reviewers` was added after the PR opened): the workflow falls back to finding the open PR by `release-pending-label`.
- A review request alone can be missed (it depends on each user's notification settings), which is why an @mention comment is also posted — mentions notify reliably. This matters when the release PR is opened by a GitHub App (`app-client-id`) rather than by you.

## Why release commits show `…[bot]` as the author

When `app-client-id` is set, the workflow mints a short-lived **GitHub App
token** (`Generate App token` → `Release Please` steps) and release-please uses
it to author the `chore(main): release X` commit (version bump + CHANGELOG).
GitHub attributes any commit made with an App token to `<app-name>[bot]`, so
that commit's **author** is the App (e.g. `release-please-global[bot]`) — while
the **committer** stays whoever merged the release PR. This is why the App shows
up in the repo's contributor list.

This is expected and intended, not a bug. Using the App identity (instead of the
default `GITHUB_TOKEN` / `github-actions[bot]`) is what lets CI run on the
release PR and bypasses the manual workflow-approval gate. Recommendations:

- **Keep it as-is (recommended).** A bot author on release-bump commits is the
  standard release-please setup and keeps your own contributions cleanly
  separated from the automated version bumps. GitHub already excludes bots from
  the repo's *contributions graph*; they only appear on the Contributors list.
- **Want the commit attributed to a human instead?** Drop `app-client-id` and
  pass a user **PAT** as `RELEASE_TOKEN` — release commits are then authored by
  that user. Trade-offs: a PAT is broader-scoped and harder to rotate than a
  per-repo App, and you lose the App's least-privilege model.
- **Don't try to block this bot via `check-bot-commits`.** If you run that guard
  on release PRs, add `release-please-global[bot]` (or your App's login) to its
  `allowed-bots` list — otherwise it will fail the release PR.
