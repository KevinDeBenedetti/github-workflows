# github-workflows

[![CI](https://img.shields.io/github/actions/workflow/status/KevinDeBenedetti/github-workflows/ci-cd.yml?style=for-the-badge&label=CI)](https://github.com/KevinDeBenedetti/github-workflows/actions/workflows/ci-cd.yml)

> Reusable GitHub Actions workflows and composite actions for Node.js, Python, shell, Helm, Terraform, and Ansible projects.

## Features

- CI pipelines for Node.js (lint → typecheck → test → build), Python (lint → format → test), and shell (ShellCheck → actionlint → Bats)
- CI pipelines for **Helm** (lint + template dry-run), **Kubernetes** (kubeconform validation), **Terraform** (validate + fmt check), and **Ansible** (lint + syntax check)
- CD workflows for Docker/GHCR, Kaniko (self-hosted), GitHub Pages, Vercel, and centralized docs sync
- Composite actions for Node.js/Python setup with caching, ShellCheck, Bats, actionlint, kubeconform, and monorepo change detection
- Automated releases via release-please
- Security scanning: dependency audit, CodeQL, and secret detection
- Pre-commit hooks via [prek](https://prek.j178.dev) for local validation

## Prerequisites

- A GitHub repository
- Appropriate secrets configured in your repo or organization (see each workflow's docs)

## Usage

Reference any workflow from your caller workflow file.

### Pinning strategy

| Stability need | Recommended pin | Example |
|---|---|---|
| Development / fast-moving | `@main` | `ci-node.yml@main` |
| Production / reproducible | Release tag | `ci-node.yml@v3.0.0` |
| Maximum reproducibility | Commit SHA | `ci-node.yml@abc1234` |

> The README and docs always reflect `@main`. When releasing, consumers should pin to a tag for reproducible builds.

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-node.yml@main
    secrets: inherit
```

→ Full usage guide: [docs](https://kevindebenedetti.github.io/github-workflows/getting-started)

## Available workflows

| Workflow | Description | Doc |
|---|---|---|
| `ci-node.yml` | Node.js CI (lint → typecheck → test → build) | [→](docs/workflows/ci-node.md) |
| `ci-python.yml` | Python CI (lint → format → test) | [→](docs/workflows/ci-python.md) |
| `ci-shell.yml` | Shell CI (ShellCheck → actionlint → Bats) | [→](docs/workflows/ci-shell.md) |
| `ci-ansible.yml` | Ansible CI (ansible-lint + syntax check) | [→](docs/workflows/ci-ansible.md) |
| `ci-helm.yml` | Helm CI (lint + template dry-run) | [→](docs/workflows/ci-helm.md) |
| `ci-kubernetes.yml` | Kubernetes CI (kubeconform manifest validation) | [→](docs/workflows/ci-kubernetes.md) |
| `ci-terraform.yml` | Terraform CI (validate + fmt check) | [→](docs/workflows/ci-terraform.md) |
| `cd-docker.yml` | Build & push multi-platform Docker image to GHCR | [→](docs/workflows/cd-docker.md) |
| `cd-kaniko.yml` | Build & push image with Kaniko on self-hosted runners | [→](docs/workflows/cd-kaniko.md) |
| `cd-pages.yml` | Build & deploy static site to GitHub Pages | [→](docs/workflows/cd-pages.md) |
| `cd-vercel.yml` | Deploy preview or production to Vercel | [→](docs/workflows/cd-vercel.md) |
| `cd-docs.yml` | Sync docs to a centralized docs repository | [→](docs/workflows/cd-docs.md) |
| `release.yml` | Automated releases via release-please | [→](docs/workflows/release.md) |
| `security.yml` | Secret scan + CodeQL SAST + dependency audit | [→](docs/workflows/security.md) |
| `check-bot-commits.yml` | Guard PRs against bot-authored commits | [→](docs/workflows/check-bot-commits.md) |

## Documentation

Full documentation is available at **https://kevindebenedetti.github.io/github-workflows/**.
It is generated from the `docs/` directory and published automatically on push.

See [`examples/`](examples/) for ready-to-copy caller workflows.
