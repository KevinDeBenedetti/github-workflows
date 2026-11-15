---
title: Action — cleanup-deployments
---

# Action — cleanup-deployments

Deletes the old deployment records of the repository, oldest first. It keeps the
`keep` most recent deployments of each environment and those younger than
`older-than-days`, and gives each deployment the `inactive` status before
deleting it. The [`cleanup-deployments`](../workflows/cleanup-deployments.md)
workflow runs it.

## Usage

```yaml
permissions:
  deployments: write
steps:
  - uses: KevinDeBenedetti/github-workflows/.github/actions/cleanup-deployments@main
    with:
      dry-run: true
```

## Inputs

| Input             | Default                                | Description                                                  |
| ----------------- | -------------------------------------- | ------------------------------------------------------------ |
| `keep`            | `5`                                    | Most recent deployments kept per environment (1 to 100)      |
| `older-than-days` | `30`                                   | Age, in days, before a deployment can be deleted (0 or more) |
| `max-deletions`   | `200`                                  | Deletions at most in one run (1 to 400), two requests each   |
| `dry-run`         | `false`                                | Log what would be deleted, delete nothing                    |
| `github-token`    | <code v-pre>${{ github.token }}</code> | Token with `deployments: write`                              |

## Outputs

| Output      | Description                                                         |
| ----------- | ------------------------------------------------------------------- |
| `deleted`   | Deployments deleted by this run (in a dry run, those that would be) |
| `remaining` | Deployments left for a later run by `max-deletions`                 |

## Notes

- Needs bash, curl and jq: no GitHub CLI.
- The script is `cleanup-deployments.sh`; its tests are in
  `tests/cleanup-deployments.bats`.
