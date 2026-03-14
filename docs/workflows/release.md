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

| Input            | Type   | Default                                        | Description                                                                                       |
| ---------------- | ------ | ---------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `release-type`   | string | `''`                                           | release-please release type (e.g. `node`, `python`, `simple`). Ignored when `config-file` is set. |
| `config-file`    | string | `release-please-config.json`                   | Path to `release-please-config.json`                                                              |
| `manifest-file`  | string | `.release-please-manifest.json`                | Path to `.release-please-manifest.json`                                                           |
| `git-user-name`  | string | `github-actions[bot]`                          | Name used for the git tagger identity when moving the major version tag                           |
| `git-user-email` | string | `github-actions[bot]@users.noreply.github.com` | Email used for the git tagger identity when moving the major version tag                          |

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
