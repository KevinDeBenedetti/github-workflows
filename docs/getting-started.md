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

> **Production tip:** Pin to a release tag (`@vX.Y.Z`) or the minor alias (`@v0.<minor>`) instead of `@main`. The workflows call their composite actions with `uses: $/…`, resolved to the workflow's own commit, so a pin covers the actions too.

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

### Docs sync

Verify this repo's docs before the centralized docs site picks them up. The site polls
public repos for `docs/` changes on a schedule, so no token, App or secret is needed.

```yaml
jobs:
  docs:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-docs.yml@main
    with:
      docs-directory: docs
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

### PR descriptions (Claude Code)

Rewrites a managed block at the top of each pull request description on every push,
from the commits and the diff. Runs on your Claude subscription: store a token from
`claude setup-token` as the `CLAUDE_CODE_OAUTH_TOKEN` secret.

```yaml
on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  describe:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/pr-description.yml@main
    permissions:
      contents: read
      pull-requests: write
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

→ [Full reference](workflows/pr-description.md)

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
| `cd-kaniko.yml` | Build & push image with Kaniko on self-hosted runners (upstream archived — see `cd-buildkit.yml`) | [→](workflows/cd-kaniko.md) |
| `cd-buildkit.yml` | Build & push image with rootless BuildKit on self-hosted runners (experimental) | [→](workflows/cd-buildkit.md) |
| `cd-pages.yml` | Build & deploy static site to GitHub Pages | [→](workflows/cd-pages.md) |
| `cd-docs.yml` | Sync docs to a centralized docs repository | [→](workflows/cd-docs.md) |
| `release.yml` | Automated releases via release-please | [→](workflows/release.md) |
| `security.yml` | Secret scan + CodeQL SAST + dependency audit | [→](workflows/security.md) |
| `check-bot-commits.yml` | Guard PRs against bot-authored commits | [→](workflows/check-bot-commits.md) |
| `pr-description.yml` | PR description written by Claude Code on every push (Claude subscription) | [→](workflows/pr-description.md) |

---

## Composite actions

Actions can be used individually inside your own workflow steps:

```yaml
steps:
  - uses: KevinDeBenedetti/github-workflows/.github/actions/setup-node@main
    with:
      node-version: '24'
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
| [`check-commit-msg`](actions/check-commit-msg.md) | Conventional Commits on commit messages (CI + commit-msg hook) |
| [`setup-ansible`](actions/setup-ansible.md) | Install ansible-lint or ansible from a hash-locked requirements file |
| [`setup-claude-code`](actions/setup-claude-code.md) | Install the Claude Code CLI, pinned and checked against a SHA-256 |
| [`pr-description`](actions/pr-description.md) | Write the PR description with Claude Code into a managed block of the PR body |
| [`check-docs-links`](actions/check-docs-links.md) | Check for broken links in docs |
| [`check-docs-external-links`](actions/check-docs-external-links.md) | Check the `http(s)` links of changed docs pages with lychee |
| [`check-vitepress-md`](actions/check-vitepress-md.md) | Validate VitePress markdown |
| [`notify-deployment`](actions/notify-deployment.md) | Post a deployment status notification |

---

## Examples

Complete ready-to-use caller files live in [`examples/`](https://github.com/KevinDeBenedetti/github-workflows/tree/main/examples):

| File | Stack |
|---|---|
| `ci-cd-pages.yml` | Node.js CI → GitHub Pages → release-please |
| `next.yml` | Next.js |
| `nuxt.yml` | Nuxt |
| `vue-react.yml` | Vue / React (Vite) |
| `fastapi.yml` | FastAPI (Python) |
| `monorepo.yml` | Monorepo with change detection |
| `vitepress.yml` | VitePress docs site |
| `pr-description.yml` | PR descriptions written by Claude Code |
