---
title: Action — propagate-release
---

# Action — propagate-release

Opens a pull request in each consumer repository that moves its pins of this
repository's workflows and actions to a release, and turns on auto-merge. Talks to the
REST and GraphQL APIs with curl and jq: no GitHub CLI needed, no checkout.
[`propagate-release.yml`](../workflows/propagate-release.md) wraps it with the GitHub
App token, and documents which pins move and how the pull request behaves.

## Usage

```yaml
steps:
  - id: app-token
    uses: actions/create-github-app-token@v3
    with:
      client-id: ${{ vars.RELEASE_APP_CLIENT_ID }}
      private-key: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}
      owner: ${{ github.repository_owner }}
      repositories: web-app,api
      permission-contents: write
      permission-pull-requests: write
      permission-workflows: write
  - uses: KevinDeBenedetti/github-workflows/.github/actions/propagate-release@main
    with:
      repositories: |
        web-app:dev
        api
      token: ${{ steps.app-token.outputs.token }}
```

## Inputs

| Input          | Default                                | Description                                                             |
| -------------- | -------------------------------------- | ----------------------------------------------------------------------- |
| `repositories` | required                               | Consumer repositories, one per line or comma-separated: `name[:branch]` |
| `tag`          | `''`                                   | Release to move to; empty means the latest release of this repository   |
| `auto-merge`   | `true`                                 | Turn on auto-merge on each pull request                                 |
| `dry-run`      | `false`                                | Log what would move, write nothing                                      |
| `token`        | required                               | Contents, pull-requests and workflows write on the consumers            |
| `source-token` | <code v-pre>${{ github.token }}</code> | Reads the releases of this repository                                   |

## Notes

- `bump-pins.py` rewrites the pins and keeps every other byte of a file, CRLF line ends
  included.
- Each token goes to curl through a header file, never on a command line.
- The job summary lists each repository with its pull request or the reason it has
  none.
