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

## Notes

- Requires **GitHub Pages** to be enabled in repository settings (source: GitHub Actions).
- The deploy job requires `pages: write` and `id-token: write` permissions (automatically granted).
- Uses `actions/upload-pages-artifact` + `actions/deploy-pages` for the two-stage build → deploy split.
