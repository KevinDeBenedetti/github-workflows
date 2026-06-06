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
```

:::

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `app-name` | Name of the application (e.g., portfolio-dev) | Yes | — |
| `environment` | Environment name (e.g., development, production) | No | `development` |
| `status` | Deployment status (success, failure) | No | `success` |
| `version` | Image version or tag | Yes | — |
| `url` | Application URL | No | — |
| `argocd-url` | ArgoCD application dashboard URL | No | — |

## Output

The action generates a formatted Markdown table in the GitHub Job Summary containing:

- ✅ or ❌ status icon
- Environment name
- Version/tag information
- Application URL (if provided)
- Links to monitoring dashboards:
  - 🛰️ ArgoCD application (if provided)
  - 📝 Infra commit link
  - 📊 Action execution logs

### Example Output

```
✅ Déploiement portfolio-dev

| Propriété | Valeur |
| :--- | :--- |
| **Statut** | ✅ success |
| **Environnement** | `development` |
| **Version** | `dev-latest` |
| **URL** | [portfolio.kevindb.dev](https://portfolio.kevindb.dev) |

Actions de monitoring :
- 🛰️ [Voir sur ArgoCD](https://argocd.kevindb.dev/applications/portfolio-dev)
- 📝 [Commit Infra](https://github.com/KevinDeBenedetti/infra/commit/main)
- 📊 [Logs de l'action](...)
```

## Tips

- Use `if: always()` to ensure notifications are sent even if previous steps fail
- Use <code v-pre>${{ job.status }}</code> to automatically capture success/failure
- Set `url` to the production endpoint for visibility
- Link to ArgoCD for synchronization status checks
