---
title: CI — Node.js
---

# CI — Node.js

Runs **lint → typecheck → test → build** for a Node.js application.
Auto-detects **pnpm**, **bun** or **npm** from the lockfile.

## Usage

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-node.yml@main
    with:
      node-version: '24'
      working-directory: '.'
```

## Inputs

| Input                 | Type    | Default | Description                                                                      |
| --------------------- | ------- | ------- | -------------------------------------------------------------------------------- |
| `node-version`        | string  | `'24'`  | Node.js version                                                                  |
| `working-directory`   | string  | `'.'`   | Path to the app root (e.g. `apps/web`)                                           |
| `package-manager`     | string  | `auto`  | `pnpm` \| `bun` \| `npm` \| `auto` — auto-detects from lockfile                  |
| `framework`           | string  | `auto`  | `next` \| `nuxt` \| `vite` \| `auto` — resolves build output path when uploading |
| `run-lint`            | boolean | `true`  | Run `lint` script                                                                |
| `run-typecheck`       | boolean | `true`  | Run `typecheck` script                                                           |
| `run-test`            | boolean | `true`  | Run `test` script                                                                |
| `test-args`           | string  | `--passWithNoTests` | Extra arguments for the `test` script (pnpm/npm) — set `''` for runners rejecting unknown flags |
| `run-build`           | boolean | `true`  | Run `build` script                                                               |
| `upload-build`        | boolean | `false` | Upload build output as a workflow artifact                                       |
| `build-artifact-name` | string  | `build` | Name of the uploaded artifact                                                    |
| `run-link-check`      | boolean | `false` | Check markdown files for broken relative links (offline, no HTTP requests)       |
| `link-check-paths`    | string  | `docs/` | Space-separated paths or directories of markdown files to check                  |
| `runner`              | string  | `'"ubuntu-26.04"'`  | Runner labels as JSON — e.g. `'"ubuntu-26.04"'` or `'"my-scale-set"'` (the name of an ARC runner scale set)  |
| `timeout-minutes`     | number  | `30`    | Minutes before the job is cancelled (GitHub's default is 360) — raise it for a slow build |

## Secrets

| Secret         | Required | Description                                                                                       |
| -------------- | -------- | ------------------------------------------------------------------------------------------------- |
| `github-token` | no       | GitHub token passed as `GITHUB_TOKEN` env var to the build step (e.g. for scripts calling the GitHub API) |

## Steps

1. Checkout
2. Setup Node.js + package manager (via [`setup-node`](https://github.com/KevinDeBenedetti/github-workflows/tree/main/.github/actions/setup-node))
3. Lint
4. Typecheck
5. Test (with `test-args`, default `--passWithNoTests`, for pnpm/npm)
6. Build
7. Upload artifact *(only when `upload-build: true`)*
8. Link check *(only when `run-link-check: true`)*; Markdown without any link passes

## Notes

- Build output path is resolved per framework: `next` → `.next`, `nuxt` → `.output`, otherwise `dist`.
- Setting `framework: auto` (default) detects the framework from config files (`next.config.*`, `nuxt.config.*`).
- Steps are individually skippable with their `run-*` flags, which is useful for partial pipelines (e.g. build-only).
- The dependency cache and the Next.js build cache are keyed on the lockfile [`setup-node`](../actions/setup-node.md) resolves — the repository root's for a workspace member — so a monorepo app gets a cache that follows its dependency set.
- `timeout-minutes` cuts off a hung install, test or build: without it a job holds the runner (and bills the minutes) for up to 6 hours.
