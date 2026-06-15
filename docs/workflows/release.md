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

## Secrets

| Secret          | Required | Description                                                                          |
| --------------- | -------- | ------------------------------------------------------------------------------------ |
| `RELEASE_TOKEN` | no       | PAT with `contents: write` and `pull-requests: write`. Falls back to `GITHUB_TOKEN`. |

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
