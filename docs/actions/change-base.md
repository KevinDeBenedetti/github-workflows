---
title: Action — change-base
---

# Action — change-base

Finds the **change base** of the run: the commit its change starts from. A
check then walks the commits `base..HEAD` (commit messages, a secret scan) or
compares the files of `base` and `HEAD` (changed docs pages, changed apps).
The workflows and actions of this repository use it wherever they need the
change of a push or pull request: the [`secret-scan`](secret-scan.md) action of `security.yml`, `ci-cd.yml`'s
commit check, [`check-docs-external-links`](check-docs-external-links.md) and
[`detect-changes`](detect-changes.md).

## Usage

```yaml
steps:
  - uses: actions/checkout@v7
    with:
      fetch-depth: 0 # a walk of base..HEAD needs the history in between
      persist-credentials: false

  - id: base
    uses: KevinDeBenedetti/github-workflows/.github/actions/change-base@main

  - if: steps.base.outputs.mode != 'none'
    uses: KevinDeBenedetti/github-workflows/.github/actions/check-commit-msg@main
    with:
      range: ${{ steps.base.outputs.base }}..HEAD
```

To compare files only, a shallow checkout is enough with `fetch-base: 'true'`.

## Inputs

| Input        | Default | Description                                                                                                   |
| ------------ | ------- | ------------------------------------------------------------------------------------------------------------- |
| `base-ref`   | `''`    | Commit, branch or tag to use instead of the lookup; the step fails when it is not in the clone (or fetchable) |
| `fetch-base` | `false` | Fetch a change base missing from a shallow clone, that one commit. For comparing files only                   |

## Outputs

| Output | Description                                                                  |
| ------ | ---------------------------------------------------------------------------- |
| `base` | Full SHA of the change base, empty when `mode` is `none`                     |
| `mode` | How it was found: `override`, `pull-request`, `push`, `fork-point` or `none` |

## Lookup

The first match wins. A candidate counts only when it is in the clone or, with
`fetch-base` on a shallow clone, can be fetched:

| Mode           | Change base                                                                                                                                                        |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `override`     | `base-ref`, when set                                                                                                                                               |
| `pull-request` | The pull request's base commit (`pull_request`, `pull_request_target`)                                                                                             |
| `push`         | The commit before the push                                                                                                                                         |
| `fork-point`   | A push whose previous commit is gone (a new branch, or a force push rewrote it away): where the branch left the default branch. Never on the default branch itself |
| `none`         | Nothing above: a manual or scheduled run, or a clone holding neither the previous commit nor the default branch                                                    |

What `none` means is the caller's choice: the secret scan scans all fetched
history, the commit check skips, the external-link check checks every page,
`detect-changes` counts every app as changed.

## Notes

- **`fetch-base` is for comparing files.** Comparing the trees of `base` and
  `HEAD` needs those two commits only. A walk of `base..HEAD` needs every
  commit in between: in a shallow clone it would stop at the edge of the clone
  without an error, so leave `fetch-base` off and check out with
  `fetch-depth: 0`.
- **`fetch-base` fetches in a shallow clone only.** A commit missing from a
  complete clone was rewritten away by a force push: nothing is fetched and
  the lookup moves on to the fork point. A shallow clone cannot tell a
  rewritten commit from one outside its depth, so after a force push the
  discarded tip is used when `origin` still serves it.
- **The fork point** needs the default branch in the clone, as
  `fetch-depth: 0` provides (it fetches every branch). On a shallow checkout a
  new branch gets `none`.
- **The other end is always `HEAD`.** On a pull request, `HEAD` is the merge
  commit GitHub prepares, so `base..HEAD` holds the pull request's commits
  plus that merge commit, which `--no-merges` leaves out.
- A fetch needs read access to `origin`: with `persist-credentials: false` it
  works on a public repository only. On a private one the lookup moves on as
  if the commit were missing, and a `base-ref` that cannot be fetched fails
  the step.
- Locally: `EVENT=push BEFORE=<sha> bash .github/actions/change-base/change-base.sh`.
