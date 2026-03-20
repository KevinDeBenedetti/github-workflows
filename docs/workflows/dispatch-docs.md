# Deploy — Docs to GitHub Pages

Deploys the `docs/` folder from the calling repository directly to GitHub Pages using `actions/upload-pages-artifact` and `actions/deploy-pages`.

## Usage

```yaml
jobs:
  deploy-docs:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-docs.yml@main
```

> **GitHub Pages must be configured** to use "GitHub Actions" as the source in the repository settings.

## Inputs

| Input            | Type   | Default  | Description                                   |
| ---------------- | ------ | -------- | --------------------------------------------- |
| `docs-directory` | string | `docs`   | Path to the docs folder to deploy             |

## Outputs

| Output     | Description                            |
| ---------- | -------------------------------------- |
| `page-url` | URL of the deployed GitHub Pages site  |

## Permissions required

The calling workflow must grant the following permissions (or use `permissions: write-all`):

```yaml
permissions:
  pages: write
  id-token: write
```

These are set internally per job via `workflow_call`, so callers using `secrets: inherit` do not need to repeat them.

## Notes

- No build step — the docs folder is uploaded as-is (static files, Markdown, HTML, etc.).
- The `page-url` output is available in subsequent jobs via `needs.<job>.outputs.page-url`.
- Designed to be called after any push that updates documentation.
