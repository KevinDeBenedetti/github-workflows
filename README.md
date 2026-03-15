# github-workflows

[![CI](https://img.shields.io/github/actions/workflow/status/KevinDeBenedetti/github-workflows/ci.yml?style=for-the-badge&label=CI)](https://github.com/KevinDeBenedetti/github-workflows/actions/workflows/ci.yml)

> Reusable GitHub Actions workflows and composite actions for Node.js, Python, and shell projects.

## Features

- CI pipelines for Node.js (lint → typecheck → test → build), Python (lint → format → test), and shell (ShellCheck → actionlint → Bats)
- Deploy workflows for Docker/GHCR, GitHub Pages, and Vercel
- Composite actions for Node.js/Python setup with caching, ShellCheck, Bats, actionlint, kubeconform, and monorepo change detection
- Automated releases via release-please
- Security scanning: dependency audit, CodeQL, and secret detection
- Pre-commit hooks via [prek](https://prek.j178.dev) for local validation

## Prerequisites

- A GitHub repository
- Appropriate secrets configured in your repo or organization (see each workflow's docs)

## Usage

Reference any workflow directly from your caller workflow file:

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-node.yml@main
    secrets: inherit
```

> Pin to a commit SHA in production for reproducible builds.

→ Full usage guide: [docs](https://kevindebenedetti.github.io/github-workflows/getting-started)

## Documentation

Full documentation is available at **https://kevindebenedetti.github.io/github-workflows/**.
It is generated from the `docs/` directory and published automatically on push.

See [`examples/`](examples/) for ready-to-copy caller workflows.
