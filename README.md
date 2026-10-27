# github-workflows

[![CI](https://img.shields.io/github/actions/workflow/status/KevinDeBenedetti/github-workflows/ci-cd.yml?style=for-the-badge&label=CI)](https://github.com/KevinDeBenedetti/github-workflows/actions/workflows/ci-cd.yml) [![Release](https://img.shields.io/github/v/release/KevinDeBenedetti/github-workflows?style=for-the-badge)](https://github.com/KevinDeBenedetti/github-workflows/releases) [![OpenSSF Scorecard](https://img.shields.io/ossf-scorecard/github.com/KevinDeBenedetti/github-workflows?style=for-the-badge&label=Scorecard)](https://scorecard.dev/viewer/?uri=github.com/KevinDeBenedetti/github-workflows) [![License](https://img.shields.io/github/license/KevinDeBenedetti/github-workflows?style=for-the-badge)](LICENSE)

> Reusable GitHub Actions workflows and composite actions for Node.js, Python, shell, Helm, Terraform, and Ansible projects.

## Features

- CI pipelines for Node.js (lint → typecheck → test → build), Python (lint → format → test), and shell (ShellCheck → actionlint → Bats)
- CI pipelines for **Helm** (lint + template dry-run), **Kubernetes** (kubeconform validation), **Terraform** (validate + fmt check), and **Ansible** (lint + syntax check)
- CD workflows for Docker/GHCR, Kaniko and BuildKit (self-hosted), GitHub Pages, and centralized docs sync
- Composite actions for Node.js/Python setup with caching, ShellCheck, Bats, actionlint, kubeconform, monorepo change detection, hash-locked ansible installs, and a checksum-pinned Claude Code setup
- Pull request descriptions written by Claude Code from the commits and the diff, on your Claude subscription
- Automated releases via release-please
- Security scanning: dependency audit, CodeQL, and secret detection
- Pre-commit hooks via [prek](https://prek.j178.dev) for local validation

## Prerequisites

- A GitHub repository
- Appropriate secrets configured in your repo or organization (see each workflow's docs)
- Self-hosted runners on **2.336.0 or newer**: the workflows reach their own composite actions with GitHub's self-repository syntax (`uses: $/…`); GitHub-hosted runners already qualify

## Usage

Reference any workflow from your caller workflow file.

### Pinning strategy

| Stability need | Recommended pin | Example |
|---|---|---|
| Development / fast-moving | `@main` | `ci-node.yml@main` |
| Follow a release line | Minor alias (pre-1.0) | `ci-node.yml@v0.<minor>` (e.g. `@v0.25`) |
| Production / reproducible | Release tag | `ci-node.yml@vX.Y.Z` (see [releases](https://github.com/KevinDeBenedetti/github-workflows/releases)) |
| Maximum reproducibility | Commit SHA | `ci-node.yml@abc1234` |

> The README and docs always reflect `@main`. When releasing, consumers should pin to a tag for reproducible builds.
>
> The workflows reach the composite actions they use (`setup-node`, `shellcheck`, …) with `uses: $/…`, which GitHub resolves to the workflow's own commit: pinning a workflow to a tag or SHA pins the actions it runs too, and `@main` runs `@main`'s actions.
>
> Before 1.0, breaking changes are released as minor bumps: this repo moves only the `v0.<minor>` alias, not `v0` (`release.yml`'s `pre-major-alias: minor`).

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
| `ci-prometheus.yml` | Prometheus CI (PromQL check + alert unit tests) | [→](docs/workflows/ci-prometheus.md) |
| `perf-sitespeed.yml` | Core Web Vitals monitoring with sitespeed.io (budget + CSV history) | [→](docs/workflows/perf-sitespeed.md) |
| `perf-unlighthouse.yml` | Lighthouse audit of every page (perf, a11y, SEO) with Unlighthouse, scheduled | [→](docs/workflows/perf-unlighthouse.md) |
| `seo-crawl.yml` | SEO crawl: broken links, redirects, missing/duplicate tags | [→](docs/workflows/seo-crawl.md) |
| `ci-prek.yml` | prek / pre-commit hooks run server-side (`prek run --all-files`) | [→](docs/workflows/ci-prek.md) |
| `cd-docker.yml` | Build & push multi-platform Docker image to GHCR | [→](docs/workflows/cd-docker.md) |
| `cd-kaniko.yml` | Build & push image with Kaniko on self-hosted runners (upstream archived — see `cd-buildkit.yml`) | [→](docs/workflows/cd-kaniko.md) |
| `cd-buildkit.yml` | Build & push image with rootless BuildKit on self-hosted runners (experimental) | [→](docs/workflows/cd-buildkit.md) |
| `cd-pages.yml` | Build & deploy static site to GitHub Pages | [→](docs/workflows/cd-pages.md) |
| `cd-docs.yml` | Sync docs to a centralized docs repository | [→](docs/workflows/cd-docs.md) |
| `release.yml` | Automated releases via release-please | [→](docs/workflows/release.md) |
| `security.yml` | Secret scan + CodeQL SAST + dependency audit | [→](docs/workflows/security.md) |
| `check-bot-commits.yml` | Guard PRs against bot-authored commits | [→](docs/workflows/check-bot-commits.md) |
| `pr-description.yml` | PR description written by Claude Code on every push (Claude subscription) | [→](docs/workflows/pr-description.md) |

## Documentation

Full documentation is available at **https://kevindebenedetti.github.io/github-workflows/**.
It is generated from the `docs/` directory and published automatically on push.

See [`examples/`](examples/) for ready-to-copy caller workflows.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

These workflows run with the tokens and secrets of the repositories that call them. See [SECURITY.md](SECURITY.md) to report a vulnerability and for safe-usage guidelines (pin a release, pass secrets explicitly, least-privilege permissions).

## License

MIT — see [LICENSE](LICENSE).
