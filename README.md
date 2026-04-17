# github-workflows

[![CI](https://img.shields.io/github/actions/workflow/status/KevinDeBenedetti/github-workflows/ci-cd.yml?style=for-the-badge&label=CI)](https://github.com/KevinDeBenedetti/github-workflows/actions/workflows/ci-cd.yml)

> Reusable GitHub Actions workflows and composite actions for Node.js, Python, shell, Helm, Terraform, and Ansible projects.

## Features

- CI pipelines for Node.js (lint → typecheck → test → build), Python (lint → format → test), and shell (ShellCheck → actionlint → Bats)
- CI pipelines for **Helm** (lint + template dry-run), **Terraform** (validate + fmt check), and **Ansible** (lint + syntax check)
- Deploy workflows for Docker/GHCR, GitHub Pages, and Vercel
- Composite actions for Node.js/Python setup with caching, ShellCheck, Bats, actionlint, kubeconform, and monorepo change detection
- Automated releases via release-please
- Security scanning: dependency audit, CodeQL, and secret detection
- Repository maintenance: purge old deployments and workflow run history
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

## Documentation

Full documentation is available at **https://kevindebenedetti.github.io/github-workflows/**.
It is generated from the `docs/` directory and published automatically on push.

See [`examples/`](examples/) for ready-to-copy caller workflows.
