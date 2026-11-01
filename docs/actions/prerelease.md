---
title: Action — prerelease
---

# Action — prerelease

Computes the next pre-release of a branch, `v<next>-<type>.<n>`, from its Conventional
Commits since the last final release tag, and can publish it as a GitHub pre-release on the
commit, never marked latest. Talks to the REST API with curl and jq: no GitHub CLI needed.
[`prerelease.yml`](../workflows/prerelease.md) wraps it and documents how the version is
computed.

## Usage

```yaml
permissions:
  contents: write # publish only; computing needs contents: read

steps:
  - uses: actions/checkout@v7
    with:
      fetch-depth: 0
      fetch-tags: true
      persist-credentials: false
  - id: prerelease
    uses: KevinDeBenedetti/github-workflows/.github/actions/prerelease@main
    with:
      mode: publish
```

## Inputs

| Input             | Default               | Description                                                                 |
| ----------------- | --------------------- | --------------------------------------------------------------------------- |
| `mode`            | `plan`                | `plan` computes only; `publish` also creates the tag and the pre-release    |
| `sha`             | <code v-pre>${{ github.sha }}</code>   | Commit to pre-release                                                       |
| `prerelease-type` | `rc`                  | Pre-release identifier                                                      |
| `config-file`     | `''`                  | release-please config holding the bump rules; empty looks for one          |
| `tag`             | `''`                  | `publish`: the tag an earlier `plan` computed, checked against this run's   |
| `github-token`    | <code v-pre>${{ github.token }}</code> | Token with `contents: write`, used only to publish                          |

## Outputs

`releasable`, `tag`, `version` and `base-tag`, as described in
[`prerelease.yml`](../workflows/prerelease.md#outputs).

## Notes

- The checkout needs the whole history and its tags: the action looks for the last final tag
  and counts the commits since.
- The token goes to curl through a header file, never on a command line.
- The release notes are written to `$RUNNER_TEMP/prerelease-notes.md` and to the job summary.
