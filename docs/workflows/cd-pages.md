# Deploy — GitHub Pages

Builds a static site and deploys it to **GitHub Pages** via the official `actions/deploy-pages`.

## Usage

```yaml
jobs:
  pages:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-pages.yml@main
    with:
      build-command: 'pnpm build'
      output-directory: dist
```

## Inputs

| Input               | Type   | Default      | Description                                             |
| ------------------- | ------ | ------------ | ------------------------------------------------------- |
| `working-directory` | string | `'.'`        | Path to the app root (e.g. `apps/client`)               |
| `node-version`      | string | `'24'`       | Node.js version                                         |
| `build-command`     | string | `''`         | Build command to run (leave empty to auto-detect from the package manager) |
| `output-directory`  | string | `dist`       | Build output directory, relative to `working-directory` |

## Secrets

| Secret         | Required | Description                                                                                       |
| -------------- | -------- | ------------------------------------------------------------------------------------------------- |
| `github-token` | no       | GitHub token passed as `GITHUB_TOKEN` env var to the build step (e.g. for scripts calling the GitHub API) |

## Outputs

| Output     | Description                           |
| ---------- | ------------------------------------- |
| `page-url` | URL of the deployed GitHub Pages site |

## Trigger only on docs changes

Because this is a reusable workflow (`workflow_call`), path filters **must** be set in the caller — not here.

**Full app / dedicated docs repo** (e.g. VitePress, Docusaurus — the whole repo is docs): no path filter needed, deploy on every push.

**Repo with a `docs/` subfolder** alongside app code: add a `paths` filter so deploys only fire when docs actually change:

```yaml
on:
  push:
    branches: [main]
    paths:
      - 'docs/**'
  pull_request:
    branches: [main]
    paths:
      - 'docs/**'
```

## VitePress

VitePress outputs to `docs/.vitepress/dist` by default. Use these inputs:

```yaml
jobs:
  deploy-docs:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-pages.yml@main
    with:
      build-command: 'pnpm docs:build'
      output-directory: docs/.vitepress/dist
```

See [`examples/vitepress.yml`](https://github.com/KevinDeBenedetti/github-workflows/blob/main/examples/vitepress.yml) for a ready-to-copy caller.

## Notes

- Requires **GitHub Pages** to be enabled in repository settings (source: GitHub Actions).
- Grant the calling job `contents: read`, `pages: write` and `id-token: write`: a reusable workflow gets at most what its caller grants.
- One deployment at a time per site (`concurrency`, as in GitHub's own Pages workflow): a run in progress is never cancelled, a queued one waits, and GitHub keeps only the newest queued run.
- Uses `actions/upload-pages-artifact` + `actions/deploy-pages` for the two-stage build → deploy split.
