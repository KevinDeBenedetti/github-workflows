# github-workflows

Reusable GitHub Actions workflows and composite actions for Node.js, Python, and shell projects.

All workflows use `workflow_call` — callers stay minimal and steps run consistently across repos.

---

## Structure

```
.github/
  actions/    # Composite actions (setup, lint, test)
  workflows/  # Reusable workflows
examples/     # Ready-to-copy caller examples
docs/         # Per-workflow reference
```

---

## Workflows

| Workflow            | Description                                  | Docs                                   |
| ------------------- | -------------------------------------------- | -------------------------------------- |
| `ci-node.yml`       | Lint → typecheck → test → build for Node.js  | [docs](docs/workflow-ci-node.md)       |
| `ci-python.yml`     | Lint → format → typecheck → test for Python  | [docs](docs/workflow-ci-python.md)     |
| `ci-shell.yml`      | ShellCheck → yamllint → Bats → Docker        | [docs](docs/workflow-ci-shell.md)      |
| `deploy-docker.yml` | Build & push multi-platform image to GHCR    | [docs](docs/workflow-deploy-docker.md) |
| `deploy-pages.yml`  | Build static site and deploy to GitHub Pages | [docs](docs/workflow-deploy-pages.md)  |
| `deploy-vercel.yml` | Deploy preview or production to Vercel       | [docs](docs/workflow-deploy-vercel.md) |
| `release.yml`       | Automated releases via release-please        | [docs](docs/workflow-release.md)       |
| `security.yml`      | Dependency audit + CodeQL + secret scanning  | [docs](docs/workflow-security.md)      |

## Actions

| Action           | Description                                        |
| ---------------- | -------------------------------------------------- |
| `setup-node`     | Install Node.js + pnpm/bun with cache              |
| `setup-python`   | Install Python + uv with cache                     |
| `shellcheck`     | Run ShellCheck on all `.sh` files                  |
| `yamllint`       | Validate YAML files                                |
| `bats`           | Run Bats shell tests                               |
| `detect-changes` | Output a JSON matrix of changed apps in a monorepo |

## Examples

See [`examples/`](examples/) for ready-to-copy caller workflows:

| File               | Stack                          |
| ------------------ | ------------------------------ |
| `ci-cd.pages.yml`  | Node.js + GitHub Pages         |
| `ci-cd.vercel.yml` | Node.js + Vercel               |
| `next.yml`         | Next.js                        |
| `nuxt.yml`         | Nuxt                           |
| `vue-react.yml`    | Vue / React (Vite)             |
| `fastapi.yml`      | FastAPI (Python)               |
| `monorepo.yml`     | Monorepo with change detection |
