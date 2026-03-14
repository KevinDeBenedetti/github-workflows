# github-workflows

Reusable GitHub Actions workflows and composite actions for Node.js, Python, and shell projects.

[![Documentation](https://img.shields.io/badge/Documentation-blue?style=for-the-badge)](https://kevindebenedetti.github.io/github-workflows/)
[![CI](https://img.shields.io/github/actions/workflow/status/KevinDeBenedetti/github-workflows/ci.yml?style=for-the-badge&label=CI)](https://github.com/KevinDeBenedetti/github-workflows/actions/workflows/ci.yml)

---

## Usage

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-node.yml@main
    secrets: inherit
```

> Pin to a commit SHA in production for reproducible builds.

---

## Workflows

| Workflow | Description |
|---|---|
| [`ci-node`](https://kevindebenedetti.github.io/github-workflows/workflows/ci-node) | Lint → typecheck → test → build for Node.js |
| [`ci-python`](https://kevindebenedetti.github.io/github-workflows/workflows/ci-python) | Lint → format → test for Python |
| [`ci-shell`](https://kevindebenedetti.github.io/github-workflows/workflows/ci-shell) | ShellCheck → actionlint → Bats |
| [`deploy-docker`](https://kevindebenedetti.github.io/github-workflows/workflows/deploy-docker) | Build & push multi-platform image to GHCR |
| [`deploy-pages`](https://kevindebenedetti.github.io/github-workflows/workflows/deploy-pages) | Build and deploy to GitHub Pages |
| [`deploy-vercel`](https://kevindebenedetti.github.io/github-workflows/workflows/deploy-vercel) | Deploy preview or production to Vercel |
| [`release`](https://kevindebenedetti.github.io/github-workflows/workflows/release) | Automated releases via release-please |
| [`security`](https://kevindebenedetti.github.io/github-workflows/workflows/security) | Dependency audit + CodeQL + secret scanning |

## Actions

| Action | Description |
|---|---|
| [`setup-node`](https://kevindebenedetti.github.io/github-workflows/actions/setup-node) | Install Node.js + pnpm/bun with cache |
| [`setup-python`](https://kevindebenedetti.github.io/github-workflows/actions/setup-python) | Install Python + uv with cache |
| [`shellcheck`](https://kevindebenedetti.github.io/github-workflows/actions/shellcheck) | Run ShellCheck on all `.sh` files |
| [`bats`](https://kevindebenedetti.github.io/github-workflows/actions/bats) | Run Bats shell tests |
| [`detect-changes`](https://kevindebenedetti.github.io/github-workflows/actions/detect-changes) | Output a JSON matrix of changed apps in a monorepo |
| [`actionlint`](https://kevindebenedetti.github.io/github-workflows/actions/actionlint) | Validate GitHub Actions workflow files |
| [`kubeconform`](https://kevindebenedetti.github.io/github-workflows/actions/kubeconform) | Validate Kubernetes manifests |

---

See [`examples/`](examples/) for ready-to-copy caller workflows and [`docs/`](docs/) for full reference.
