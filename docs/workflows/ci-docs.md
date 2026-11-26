---
title: CI — Docs
---

# CI — Docs

Checks a repository's Markdown docs: **relative links**, **links escaping the docs
folder**, **external links** of the pages a change touches, and **VitePress-safe
Markdown**. Each check is a job with its own switch.

## Usage

```yaml
jobs:
  docs:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-docs.yml@v0.56.2 # x-release-please-version
    permissions:
      contents: read
    with:
      run-docs-link-check: true
      run-docs-external-link-check: true
      run-vitepress-check: true
```

## Inputs

| Input                          | Type    | Default            | Description                                                                                          |
| ------------------------------ | ------- | ------------------ | ---------------------------------------------------------------------------------------------------- |
| `run-link-check`               | boolean | `true`             | Check markdown files for broken relative links (offline, no HTTP requests)                           |
| `link-check-paths`             | string  | `docs/**/*.md`     | Space-separated glob patterns of markdown files to check                                             |
| `run-docs-link-check`          | boolean | `false`            | Check that no relative links in `docs/` escape the `docs/` directory                                 |
| `run-docs-external-link-check` | boolean | `false`            | Check the `http(s)` links of the `docs/` markdown files changed by the push or pull request (lychee) |
| `run-vitepress-check`          | boolean | `false`            | Check `docs/` markdown for unescaped Vue interpolations that break the VitePress SSR build           |
| `docs-directory`               | string  | `docs`             | Path to the docs folder checked by `docs-link-check`, `docs-external-link-check` and `vitepress-check` |
| `runner`                       | string  | `'"ubuntu-26.04"'` | Runner labels as JSON — e.g. `'"ubuntu-26.04"'` or `'"ubicloud-standard-2"'`                         |

## Jobs

| Job                        | Condition                            |
| -------------------------- | ------------------------------------ |
| `link-check`               | `run-link-check: true`               |
| `docs-link-check`          | `run-docs-link-check: true`          |
| `docs-external-link-check` | `run-docs-external-link-check: true` |
| `vitepress-check`          | `run-vitepress-check: true`          |

## Notes

- `link-check` runs [lychee](https://github.com/lycheeverse/lychee) in offline mode — no external HTTP requests are made. Markdown without any link passes.
- `docs-link-check` uses the [`check-docs-links`](../actions/check-docs-links.md) action.
- `docs-external-link-check` uses the [`check-docs-external-links`](../actions/check-docs-external-links.md) action — lychee online, on the `docs/` files the push or pull request changed only, with github.com links checked through the job token.
- `vitepress-check` uses the [`check-vitepress-md`](../actions/check-vitepress-md.md) action — guards against <code v-pre>{{ }}</code> interpolations that crash the VitePress SSR build (see [cd-docs](./cd-docs.md)).
- No job needs a secret: the checkouts take no submodule.
- Every job is cut off after 15 minutes.
- [`ci-shell`](./ci-shell.md) and [`ci-node`](./ci-node.md) carried these checks before. Their inputs of the same names still work, with a warning, until the next breaking release: move the `with:` keys to a call of this workflow.
