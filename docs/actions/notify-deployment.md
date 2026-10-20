# notify-deployment

Composite action that generates a GitHub Job Summary with deployment details, environment information, and links to monitoring dashboards.

## Usage

::: v-pre

```yaml
- name: Notify Deployment
  if: always()
  uses: KevinDeBenedetti/github-workflows/.github/actions/notify-deployment@main
  with:
    app-name: 'portfolio-dev'
    environment: 'development'
    status: ${{ job.status }}
    version: 'dev-latest'
    url: 'portfolio.kevindb.dev'
    argocd-url: 'https://argocd.kevindb.dev/applications/portfolio-dev'
    infra-commit-url: 'https://github.com/KevinDeBenedetti/infra/commit/main'
```

:::

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `app-name` | Name of the application (e.g., portfolio-dev) | Yes | — |
| `environment` | Environment name (e.g., development, production) | No | `development` |
| `status` | Deployment status (success, failure) | No | `success` |
| `version` | Image version or tag | Yes | — |
| `url` | Application URL, with or without scheme (`https://` is added when missing) | No | — |
| `argocd-url` | ArgoCD application dashboard URL | No | — |
| `infra-commit-url` | Link to the infra commit behind the deployment | No | — |
| `infra-link-label` | Text of that link (e.g. `Infra PR` when the URL points to a pull request) | No | `Infra commit` |

## Output

The action generates a formatted Markdown table in the GitHub Job Summary containing:

- ✅ or ❌ status icon
- Environment name
- Version/tag information
- Application URL (if provided)
- Links to monitoring dashboards:
  - 🛰️ ArgoCD application (if provided)
  - 📝 Infra commit (if provided)
  - 📊 Workflow run logs

### Example Output

```
✅ Deployment portfolio-dev

| Property | Value |
| :--- | :--- |
| **Status** | ✅ success |
| **Environment** | `development` |
| **Version** | `dev-latest` |
| **URL** | [portfolio.kevindb.dev](https://portfolio.kevindb.dev) |

Monitoring:
- 🛰️ [View in ArgoCD](https://argocd.kevindb.dev/applications/portfolio-dev)
- 📝 [Infra commit](https://github.com/KevinDeBenedetti/infra/commit/main)
- 📊 [Workflow run logs](...)
```

## Tips

- Use `if: always()` to ensure notifications are sent even if previous steps fail
- Use <code v-pre>${{ job.status }}</code> to automatically capture success/failure
- Set `url` to the production endpoint for visibility
- Link to ArgoCD for synchronization status checks
