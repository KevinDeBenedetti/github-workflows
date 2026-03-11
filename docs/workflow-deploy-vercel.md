# Deploy — Vercel

Deploys a preview or production build to **Vercel** using the Vercel CLI.
On pull requests, automatically posts or updates a comment with the preview URL.

## Usage

```yaml
jobs:
  deploy:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/deploy-vercel.yml@main
    with:
      environment: preview
    secrets:
      VERCEL_TOKEN: ${{ secrets.VERCEL_TOKEN }}
      VERCEL_ORG_ID: ${{ secrets.VERCEL_ORG_ID }}
      VERCEL_PROJECT_ID: ${{ secrets.VERCEL_PROJECT_ID }}
```

## Inputs

| Input               | Type   | Default   | Description                                   |
| ------------------- | ------ | --------- | --------------------------------------------- |
| `environment`       | string | `preview` | Target environment: `preview` \| `production` |
| `working-directory` | string | `'.'`     | Path to the app root (e.g. `apps/web`)        |
| `node-version`      | string | `'20'`    | Node.js version                               |

## Secrets

| Secret              | Required | Description                  |
| ------------------- | -------- | ---------------------------- |
| `VERCEL_TOKEN`      | yes      | Vercel personal access token |
| `VERCEL_ORG_ID`     | yes      | Vercel team/org ID           |
| `VERCEL_PROJECT_ID` | yes      | Vercel project ID            |

## Outputs

| Output           | Description                  |
| ---------------- | ---------------------------- |
| `deployment-url` | URL of the Vercel deployment |

## Notes

- Uses `vercel pull` → `vercel build` → `vercel deploy --prebuilt` to avoid a second build on Vercel's side.
- When `environment: production`, the `--prod` flag is passed to both `vercel build` and `vercel deploy`.
- On pull requests with `environment: preview`, an existing preview comment is updated rather than a new one being created.
- Deploy concurrency is set to `cancel-in-progress: false` to preserve running deployments.
