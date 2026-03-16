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
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci/node.yml@main
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
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci/python.yml@main
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
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci/shell.yml@main
    secrets: inherit
```

Runs ShellCheck → actionlint → Bats.  
→ [Full reference](workflows/ci-shell.md)

---

### Docker

```yaml
jobs:
  deploy:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd/docker.yml@main
    with:
      image-name: my-app
      tag-latest: true
    secrets: inherit
```

Builds and pushes a multi-platform image to GHCR (`ghcr.io`).  
→ [Full reference](workflows/deploy-docker.md)

---

### GitHub Pages

```yaml
jobs:
  deploy:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd/pages.yml@main
    with:
      output-directory: dist
    secrets: inherit
```

→ [Full reference](workflows/deploy-pages.md)

---

### Vercel

Requires three secrets: `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`.

```yaml
jobs:
  deploy:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd/vercel.yml@main
    with:
      environment: preview
    secrets: inherit
```

→ [Full reference](workflows/deploy-vercel.md)

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

---

## Examples

Complete ready-to-use caller files live in [`examples/`](https://github.com/KevinDeBenedetti/github-workflows/tree/main/examples):

| File | Stack |
|---|---|
| `ci-cd.pages.yml` | Node.js CI → GitHub Pages → release-please |
| `ci-cd.vercel.yml` | Node.js CI → Vercel → release-please |
| `next.yml` | Next.js |
| `nuxt.yml` | Nuxt |
| `vue-react.yml` | Vue / React (Vite) |
| `fastapi.yml` | FastAPI (Python) |
| `monorepo.yml` | Monorepo with change detection |
