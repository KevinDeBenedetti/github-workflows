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
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
    with:
      persist-credentials: false

  - uses: KevinDeBenedetti/github-workflows/.github/actions/move-release-aliases@v0.57.0 # x-release-please-version
    with:
      tag: v1.2.3
```

## Inputs

| Input             | Default                                        | Description                                                                                        |
| ----------------- | ---------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `tag`             | —                                              | The release tag, `vMAJOR.MINOR.PATCH`, with an optional component prefix or pre-release (required) |
| `classify-only`   | `'false'`                                      | `'true'` only sets the `prerelease` output: no checkout, token or identity needed                  |
| `pre-major-alias` | `both`                                         | Aliases a `v0.x` release moves: `both` (`v0`, `v0.<minor>`), `minor`, `major`                      |
| `git-user-name`   | `github-actions[bot]`                          | Name of the tagger of the alias tags                                                               |
| `git-user-email`  | `github-actions[bot]@users.noreply.github.com` | Email of the tagger of the alias tags                                                              |
| `github-token`    | <code v-pre>${{ github.token }}</code>         | Token with contents write, used for the push only                                                  |

## Outputs

| Output       | Description                                                                         |
| ------------ | ----------------------------------------------------------------------------------- |
| `prerelease` | `'true'` when the tag is a semver pre-release (`v1.3.0-rc.2`), which moves no alias |

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
- A component tag works too: `my-lib-v2.0.1` moves `my-lib-v2`, and before 1.0 `pre-major-alias` applies under the component's prefix (`my-lib-v0.3.1` moves `my-lib-v0` and `my-lib-v0.3` with `both`).
- **A pre-release moves nothing**: `v1.3.0-rc.2` leaves `v1` on the last final
  release. A tag that is not `vMAJOR.MINOR.PATCH[-pre]` (`v1.2`,
  `v1.2.3+build`) fails the step. `release.yml` computes its `prerelease`
  output with `classify-only`, so both jobs apply one rule;
  `tests/fixtures/release-tags.tsv` holds the tags every release-tag rule of
  this repository is tested against.
- The token is passed to git through the step's environment and never written
  to `.git/config`.
