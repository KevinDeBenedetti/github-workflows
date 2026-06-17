# Getting Started

`KevinDeBenedetti/github-workflows` is a library of reusable GitHub Actions workflows
and composite actions. Callers stay minimal — CI steps run consistently across all your repos.

## Prerequisites

- A GitHub repository
- Appropriate secrets set in your repo/org (see each workflow's docs)

## How it works

Workflows are called with `workflow_call` and referenced from your own workflow files:

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/<name>.yml@main
    secrets: inherit
```

> **Production tip:** Pin to a commit SHA instead of `@main` for reproducible builds.

> **Important:** All workflow files must live at the flat root of `.github/workflows/`.
> GitHub Actions does not support reusable workflows in subdirectories.

---

## Quick start by stack

### Node.js

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-node.yml@main
    secrets: inherit
```

Auto-detects `pnpm` or `bun` from your lockfile. Runs lint → typecheck → test → build.
→ [Full reference](workflows/ci-node.md)

---

### Python

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-python.yml@main
    secrets: inherit
```

Uses `uv` and `ruff`. Runs lint → format check → test.
→ [Full reference](workflows/ci-python.md)

---

### Shell scripts

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-shell.yml@main
    secrets: inherit
```

Runs ShellCheck → actionlint → Bats.
→ [Full reference](workflows/ci-shell.md)

---

### Helm

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-helm.yml@main
    with:
      chart-paths: 'charts/*'
      run-template: true
    secrets: inherit
```

Runs `helm lint` and an optional `helm template` dry-run on all charts.

---

### Kubernetes

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-kubernetes.yml@main
    with:
      kubeconform-paths: kubernetes/
    secrets: inherit
```

Validates Kubernetes manifests with kubeconform (CRDs-catalog enabled by default).

---

### Terraform

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-terraform.yml@main
    with:
      tf-dir: terraform
    secrets: inherit
```

Runs `terraform validate` and `terraform fmt -check -diff`.

---

### Ansible

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-ansible.yml@main
    with:
      ansible-dir: ansible/
      run-syntax-check: true
    secrets: inherit
```

Runs `ansible-lint` and an optional `ansible-playbook --syntax-check`.

---

### Docker

```yaml
jobs:
  deploy:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-docker.yml@main
    with:
      image-name: my-app
      tag-latest: true
    secrets: inherit
```

Builds and pushes a multi-platform image to GHCR (`ghcr.io`).
→ [Full reference](workflows/cd-docker.md)

---

### Kaniko (self-hosted)

```yaml
jobs:
  deploy:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-kaniko.yml@main
    with:
      image-name: my-app
      runner: '["self-hosted","linux","k3s","kaniko"]'
    secrets: inherit
```

Builds and pushes an image to GHCR using Kaniko on self-hosted runners (no Docker daemon required).

---

### GitHub Pages

```yaml
jobs:
  deploy:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-pages.yml@main
    with:
      output-directory: dist
    secrets: inherit
```

→ [Full reference](workflows/cd-pages.md)

---

### Vercel

Requires three secrets: `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`.

```yaml
jobs:
  deploy:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-vercel.yml@main
    with:
      environment: preview
    secrets: inherit
```

→ [Full reference](workflows/cd-vercel.md)

---

### Docs sync

Sync this repo's docs to a centralized docs site via `repository_dispatch`. Requires a
GitHub App: pass its `client-id` and the `APP_PRIVATE_KEY` secret.

```yaml
jobs:
  docs:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-docs.yml@main
    with:
      docs-directory: docs
      client-id: ${{ vars.DOCS_APP_CLIENT_ID }}
    secrets:
      APP_PRIVATE_KEY: ${{ secrets.DOCS_APP_PRIVATE_KEY }}
```

→ [Full reference](workflows/cd-docs.md)

---

### Automated releases

```yaml
jobs:
  release:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/release.yml@main
    secrets: inherit
```

Uses [release-please](https://github.com/googleapis/release-please). Automatically moves a `v<major>` tag after each release.
→ [Full reference](workflows/release.md)

---

### Security scanning

```yaml
jobs:
  security:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/security.yml@main
    secrets: inherit
```

Combines Gitleaks secret scanning, CodeQL SAST, and optional dependency audits.
→ [Full reference](workflows/security.md)

---

## All available workflows

| Workflow | Description | Doc |
|---|---|---|
| `ci-node.yml` | Node.js CI (lint → typecheck → test → build) | [→](workflows/ci-node.md) |
| `ci-python.yml` | Python CI (lint → format → test) | [→](workflows/ci-python.md) |
| `ci-shell.yml` | Shell CI (ShellCheck → actionlint → Bats) | [→](workflows/ci-shell.md) |
| `ci-ansible.yml` | Ansible CI (ansible-lint + syntax check) | [→](workflows/ci-ansible.md) |
| `ci-helm.yml` | Helm CI (lint + template dry-run) | [→](workflows/ci-helm.md) |
| `ci-kubernetes.yml` | Kubernetes CI (kubeconform manifest validation) | [→](workflows/ci-kubernetes.md) |
| `ci-terraform.yml` | Terraform CI (validate + fmt check) | [→](workflows/ci-terraform.md) |
| `cd-docker.yml` | Build & push multi-platform Docker image to GHCR | [→](workflows/cd-docker.md) |
| `cd-kaniko.yml` | Build & push image with Kaniko on self-hosted runners | [→](workflows/cd-kaniko.md) |
| `cd-pages.yml` | Build & deploy static site to GitHub Pages | [→](workflows/cd-pages.md) |
| `cd-vercel.yml` | Deploy preview or production to Vercel | [→](workflows/cd-vercel.md) |
| `cd-docs.yml` | Sync docs to a centralized docs repository | [→](workflows/cd-docs.md) |
| `release.yml` | Automated releases via release-please | [→](workflows/release.md) |
| `security.yml` | Secret scan + CodeQL SAST + dependency audit | [→](workflows/security.md) |
| `check-bot-commits.yml` | Guard PRs against bot-authored commits | [→](workflows/check-bot-commits.md) |

---

## Composite actions

Actions can be used individually inside your own workflow steps:

```yaml
steps:
  - uses: KevinDeBenedetti/github-workflows/.github/actions/setup-node@main
    with:
      node-version: '20'
```

| Action | Description |
|---|---|
| [`setup-node`](actions/setup-node.md) | Install Node.js + pnpm/bun with cache |
| [`setup-python`](actions/setup-python.md) | Install Python + uv with cache |
| [`shellcheck`](actions/shellcheck.md) | Run ShellCheck on all `.sh` files |
| [`bats`](actions/bats.md) | Run Bats shell unit tests |
| [`detect-changes`](actions/detect-changes.md) | Output a JSON matrix of changed apps in a monorepo |
| [`actionlint`](actions/actionlint.md) | Validate GitHub Actions workflow files |
| [`kubeconform`](actions/kubeconform.md) | Validate Kubernetes manifests |
| [`check-docs-links`](actions/check-docs-links.md) | Check for broken links in docs |
| [`check-vitepress-md`](actions/check-vitepress-md.md) | Validate VitePress markdown |
| [`notify-deployment`](actions/notify-deployment.md) | Post a deployment status notification |
| [`ai-commit-msg`](actions/ai-commit-msg.md) | Pre-fill commit messages from the staged diff via Claude (pre-commit hook) |

---

## Examples

Complete ready-to-use caller files live in [`examples/`](https://github.com/KevinDeBenedetti/github-workflows/tree/main/examples):

| File | Stack |
|---|---|
| `ci-cd-pages.yml` | Node.js CI → GitHub Pages → release-please |
| `ci-cd-vercel.yml` | Node.js CI → Vercel → release-please |
| `next.yml` | Next.js |
| `nuxt.yml` | Nuxt |
| `vue-react.yml` | Vue / React (Vite) |
| `fastapi.yml` | FastAPI (Python) |
| `monorepo.yml` | Monorepo with change detection |
| `vitepress.yml` | VitePress docs site |
