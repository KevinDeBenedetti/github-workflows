---
title: Action — move-release-aliases
---

# Action — move-release-aliases

Moves the alias tags of a release, so that callers pinned to them receive it:
`v1.2.3` moves `v1`. It is the `tag-workflows` job of
[`release.yml`](../workflows/release.md), usable on its own after any release.

## Usage

```yaml
permissions:
  contents: write # move the alias tags

steps:
  - uses: actions/checkout@v7
    with:
      persist-credentials: false

  - uses: KevinDeBenedetti/github-workflows/.github/actions/move-release-aliases@main
    with:
      tag: v1.2.3
```

## Inputs

| Input             | Default                                        | Description                                                                   |
| ----------------- | ---------------------------------------------- | ----------------------------------------------------------------------------- |
| `tag`             | —                                              | The release tag, `vMAJOR.MINOR.PATCH` (required)                              |
| `pre-major-alias` | `both`                                         | Aliases a `v0.x` release moves: `both` (`v0`, `v0.<minor>`), `minor`, `major` |
| `git-user-name`   | `github-actions[bot]`                          | Name of the tagger of the alias tags                                          |
| `git-user-email`  | `github-actions[bot]@users.noreply.github.com` | Email of the tagger of the alias tags                                         |
| `github-token`    | <code v-pre>${{ github.token }}</code>         | Token with contents write, used for the push only                             |

## Notes

- **Before 1.0**, semver promises no stability inside `0.x`, so `v0.24.3`
  moves `v0.24` as well as `v0` by default: a caller pinned to `@v0.24` is not
  carried across a breaking minor release.
- **Safe to re-run.** Each alias is fetched from the remote first: one that
  already points at the release is left alone, and a push rejected because
  another job moved the alias in between is retried, three times at most.
- The alias is an annotated tag on the **release commit**, whatever the
  checkout sits on. The release tag is fetched, so a shallow checkout is
  enough.
- A component tag works too: `my-lib-v2.0.1` moves `my-lib-v2`.
- The token is passed to git through the step's environment and never written
  to `.git/config`.
