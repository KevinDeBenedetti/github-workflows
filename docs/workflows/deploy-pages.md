# Deploy — GitHub Pages

Builds a static site and deploys it to **GitHub Pages** via the official `actions/deploy-pages`.

## Usage

```yaml
jobs:
  pages:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/deploy-pages.yml@main
    with:
      build-command: 'pnpm build'
      output-directory: dist
```

## Inputs

| Input               | Type   | Default      | Description                                             |
| ------------------- | ------ | ------------ | ------------------------------------------------------- |
| `working-directory` | string | `'.'`        | Path to the app root (e.g. `apps/client`)               |
| `node-version`      | string | `'20'`       | Node.js version                                         |
| `build-command`     | string | `pnpm build` | Command to build the static site                        |
| `output-directory`  | string | `dist`       | Build output directory, relative to `working-directory` |

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
    uses: KevinDeBenedetti/github-workflows/.github/workflows/deploy-pages.yml@main
    with:
      build-command: 'pnpm docs:build'
      output-directory: docs/.vitepress/dist
    secrets: inherit
```

See [`examples/vitepress.yml`](https://github.com/KevinDeBenedetti/github-workflows/blob/main/examples/vitepress.yml) for a ready-to-copy caller.

## Notes

- Requires **GitHub Pages** to be enabled in repository settings (source: GitHub Actions).
- The deploy job requires `pages: write` and `id-token: write` permissions (automatically granted).
- Uses `actions/upload-pages-artifact` + `actions/deploy-pages` for the two-stage build → deploy split.
