# CI — Node.js

Runs **lint → typecheck → test → build** for a Node.js application.
Auto-detects **pnpm** or **bun** from the lockfile.

## Usage

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-node.yml@main
    with:
      node-version: '20'
      working-directory: '.'
```

## Inputs

| Input                 | Type    | Default | Description                                                                      |
| --------------------- | ------- | ------- | -------------------------------------------------------------------------------- |
| `node-version`        | string  | `'20'`  | Node.js version                                                                  |
| `working-directory`   | string  | `'.'`   | Path to the app root (e.g. `apps/web`)                                           |
| `package-manager`     | string  | `auto`  | `pnpm` \| `bun` \| `auto` — auto-detects from lockfile                           |
| `framework`           | string  | `auto`  | `next` \| `nuxt` \| `vite` \| `auto` — resolves build output path when uploading |
| `run-lint`            | boolean | `true`  | Run `lint` script                                                                |
| `run-typecheck`       | boolean | `true`  | Run `typecheck` script                                                           |
| `run-test`            | boolean | `true`  | Run `test` script                                                                |
| `run-build`           | boolean | `true`  | Run `build` script                                                               |
| `upload-build`        | boolean | `false` | Upload build output as a workflow artifact                                       |
| `build-artifact-name` | string  | `build` | Name of the uploaded artifact                                                    |
| `run-link-check`      | boolean | `false` | Check markdown files for broken relative links (offline, no HTTP requests)       |
| `link-check-paths`    | string  | `docs/**/*.md` | Space-separated glob patterns of markdown files to check                  |

## Steps

1. Checkout
2. Setup Node.js + package manager (via [`setup-node`](https://github.com/KevinDeBenedetti/github-workflows/tree/main/.github/actions/setup-node))
3. Lint
4. Typecheck
5. Test (`--passWithNoTests`)
6. Build
7. Upload artifact *(only when `upload-build: true`)*
8. Link check *(only when `run-link-check: true`)*

## Notes

- Build output path is resolved per framework: `next` → `.next`, `nuxt` → `.output`, otherwise `dist`.
- Setting `framework: auto` (default) detects the framework from config files (`next.config.*`, `nuxt.config.*`).
- Steps are individually skippable with their `run-*` flags, which is useful for partial pipelines (e.g. build-only).
