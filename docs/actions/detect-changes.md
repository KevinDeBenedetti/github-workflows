---
title: Action — detect-changes
---

# Action — detect-changes

Detects which subdirectories under `apps/` (or a custom directory) have changed since the
change base of the run (the pull request's base, the commit before the push, or a new
branch's fork point with the default branch), and outputs a JSON matrix for use in
downstream matrix jobs.

## Usage

```yaml
jobs:
  detect:
    runs-on: ubuntu-26.04
    outputs:
      changed-apps: ${{ steps.changes.outputs.changed-apps }}
      has-changes:  ${{ steps.changes.outputs.has-changes }}
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0

      - uses: KevinDeBenedetti/github-workflows/.github/actions/detect-changes@main
        id: changes
        with:
          apps-directory: apps

  build:
    needs: detect
    if: needs.detect.outputs.has-changes == 'true'
    strategy:
      matrix:
        app: ${{ fromJson(needs.detect.outputs.changed-apps) }}
    runs-on: ubuntu-26.04
    steps:
      - run: echo "Building ${{ matrix.app }}"
```

## Inputs

| Input            | Type   | Default | Description                                                         |
| ---------------- | ------ | ------- | ------------------------------------------------------------------- |
| `apps-directory` | string | `apps`  | Root directory containing app subdirectories                        |
| `base-ref`       | string | `''`    | Commit, branch or tag to compare against instead of the change base |

## Outputs

| Output           | Description                                           |
| ---------------- | ----------------------------------------------------- |
| `changed-apps`   | JSON array of changed app names, e.g. `["api","web"]` |
| `has-changes`    | `"true"` or `"false"` — whether any app changed       |
| `changed-api`    | `"true"` or `"false"` — whether `apps/api` changed    |
| `changed-web`    | `"true"` or `"false"` — whether `apps/web` changed    |
| `changed-client` | `"true"` or `"false"` — whether `apps/client` changed |

## Change base

The action finds it with [`change-base`](change-base.md), `fetch-base` on:

1. `base-ref`, when set. The action fails when it is not a commit of the clone and cannot
   be fetched.
2. The pull request's base commit on a pull request.
3. The commit before the push on a push.
4. On a push whose previous commit is gone (a new branch, a force push): the fork point with
   the default branch. This needs the default branch in the clone, which `fetch-depth: 0`
   provides.
5. Otherwise (a manual or scheduled run, or a shallow clone holding neither): no change base,
   and **every app counts as changed**, with a warning. No app is skipped unnoticed.

## Notes

- Needs runner 2.336.0 or newer: the action calls `change-base` with `uses: $/…`, which
  GitHub Enterprise Server does not support.
- Use `fetch-depth: 0` in your checkout step, so a new branch is compared with its fork point.
  A shallow checkout still works for pull requests and pushes: the base commit is fetched,
  that one commit. On a private repository this fetch needs the checkout's credentials, so
  keep `persist-credentials` on or use `fetch-depth: 0`.
- Per-app boolean outputs (`changed-api`, `changed-web`, `changed-client`) are useful for
  `if:` conditions when you don't need a matrix. Composite actions cannot declare outputs
  dynamically, so only these three names exist; for any other app test `changed-apps`, e.g.
  `contains(fromJson(steps.changes.outputs.changed-apps), 'admin')`.
- App names are sanitized (lowercased, non-alphanumeric characters replaced with `_`) in the
  output key names.
