---
title: Getting Started
---

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
```

Pass a workflow only the secrets it declares (a `secrets:` block naming each one) and grant the calling job only the permissions its page lists — never `secrets: inherit`. A reusable workflow gets at most what its caller grants. See the [security policy](https://github.com/KevinDeBenedetti/github-workflows/blob/main/SECURITY.md).

> **Production tip:** Pin to a release tag (`@vX.Y.Z`) or the minor alias (`@v0.<minor>`) instead of `@main`. The workflows call their composite actions with `uses: $/…`, resolved to the workflow's own commit, so a pin covers the actions too.

GitHub-hosted jobs run on `ubuntu-26.04`, a pinned image rather than `ubuntu-latest`: when GitHub moves `ubuntu-latest` to a new Ubuntu release, your jobs only change image with a release of these workflows, like any other change. A workflow with a `runner` input runs on any other label — another image (`runner: '["ubuntu-24.04"]'`), an arm64 runner or an Ubicloud runner (`runner: '"ubicloud-standard-2"'`).

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
```

Runs ShellCheck → actionlint → Bats.
→ [Full reference](workflows/ci-shell.md)

---

### Kubernetes

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-kubernetes.yml@main
    with:
      kubeconform-paths: kubernetes/
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
```

Runs `terraform validate` and `terraform fmt -check -diff`.

---

### Docker

```yaml
jobs:
  deploy:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-docker.yml@main
    permissions:
      contents: read
      packages: write      # push the image to GHCR
      deployments: write   # production/preview environment record
      id-token: write      # sign the image attestation (Sigstore)
      attestations: write  # store the attestation
    with:
      image-name: my-app
      tag-latest: true
```

Builds and pushes an image to GHCR (`ghcr.io`), for one or several platforms, on a GitHub-hosted or Ubicloud runner.
→ [Full reference](workflows/cd-docker.md)

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
    # No token secret: release-please runs on GITHUB_TOKEN (enable "Allow
    # GitHub Actions to create and approve pull requests" in the repo settings).
    permissions:
      contents: write        # release branch, tags and releases
      issues: write          # release-please labels the release PR
      pull-requests: write   # open/update the release PR
```

Uses [release-please](https://github.com/googleapis/release-please). Automatically moves a `v<major>` tag after each release.
→ [Full reference](workflows/release.md)

---

### Security scanning

```yaml
jobs:
  security:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/security.yml@main
    permissions:
      security-events: write  # upload the Gitleaks and CodeQL results to code scanning
      actions: read           # code scanning reads the workflow run metadata
      contents: read
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

### GHCR cleanup

Deletes old image versions in GHCR every week, from the repository that publishes
them. Release tags, moving tags and images younger than 30 days are never deleted.

```yaml
on:
  schedule:
    - cron: "23 4 * * 1"
  workflow_dispatch:

jobs:
  cleanup:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cleanup-ghcr.yml@main
    permissions:
      packages: write
    with:
      packages: my-app   # default: the repository name
      dry-run: true      # remove once a manual run's log looks right
```

→ [Full reference](workflows/cleanup-ghcr.md)

---

### Workflow runs cleanup

Deletes old workflow runs, with their logs and artifacts, every week. Runs younger
than 30 days, the 10 most recent runs of each workflow and the runs of open pull
requests are never deleted; a deleted workflow file leaves the Actions sidebar.
`artifacts-older-than-days` also deletes the old artifacts of the runs kept, which
count against the account's Actions storage.

```yaml
on:
  schedule:
    - cron: "43 4 * * 1"
  workflow_dispatch:

jobs:
  cleanup:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cleanup-runs.yml@main
    permissions:
      actions: write
      pull-requests: read
    with:
      artifacts-older-than-days: 3 # the runs kept lose their old artifacts too
      dry-run: true      # remove once a manual run's log looks right
```

→ [Full reference](workflows/cleanup-runs.md)

---

## All available workflows

| Workflow                  | Description                                                                                                                            | Doc                                   |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- |
| `ci-node.yml`             | Node.js CI (lint → typecheck → test → build)                                                                                           | [→](workflows/ci-node.md)             |
| `ci-python.yml`           | Python CI (lint → format → test)                                                                                                       | [→](workflows/ci-python.md)           |
| `ci-shell.yml`            | Shell CI (ShellCheck → actionlint → Bats)                                                                                              | [→](workflows/ci-shell.md)            |
| `ci-docs.yml`             | Docs CI (relative and external links, VitePress-safe Markdown)                                                                         | [→](workflows/ci-docs.md)             |
| `ci-kubernetes.yml`       | Kubernetes CI (kubeconform on manifests, charts, kustomizations)                                                                       | [→](workflows/ci-kubernetes.md)       |
| `ci-terraform.yml`        | Terraform CI (validate, fmt, tflint, config scan)                                                                                      | [→](workflows/ci-terraform.md)        |
| `ci-prometheus.yml`       | Prometheus CI (PromQL check + alert unit tests)                                                                                        | [→](workflows/ci-prometheus.md)       |
| `ci-prek.yml`             | prek / pre-commit hooks run server-side (`prek run --all-files`)                                                                       | [→](workflows/ci-prek.md)             |
| `ci-docker.yml`           | Build a Docker image without pushing it, with a read-only token                                                                        | [→](workflows/ci-docker.md)           |
| `cd-docker.yml`           | Build & push a Docker image to GHCR, for one or several platforms                                                                      | [→](workflows/cd-docker.md)           |
| `cd-docs.yml`             | Sync docs to a centralized docs repository                                                                                             | [→](workflows/cd-docs.md)             |
| `release.yml`             | Automated releases via release-please                                                                                                  | [→](workflows/release.md)             |
| `propagate-release.yml`   | A pull request in each consumer repository moves its pins to the new release                                                           | [→](workflows/propagate-release.md)   |
| `renovate.yml`            | Renovate run with a GitHub App's token, on the shared preset `KevinDeBenedetti/renovate-config`                                        | [→](workflows/renovate.md)            |
| `security.yml`            | Secret scan + CodeQL SAST + dependency audit                                                                                           | [→](workflows/security.md)            |
| `check-bot-commits.yml`   | Guard PRs against bot-authored commits                                                                                                 | [→](workflows/check-bot-commits.md)   |
| `pr-description.yml`      | PR description written by Claude Code on every push (Claude subscription)                                                              | [→](workflows/pr-description.md)      |
| `cleanup-ghcr.yml`        | Scheduled GHCR retention: keeps releases and recent images, deletes the rest and old layer caches                                      | [→](workflows/cleanup-ghcr.md)        |
| `cleanup-runs.yml`        | Scheduled workflow-run retention: keeps recent runs and the last runs of each workflow, deletes the rest, and optionally old artifacts | [→](workflows/cleanup-runs.md)        |
| `cleanup-deployments.yml` | Scheduled cleanup of old deployment records, keeping the recent ones of each environment                                               | [→](workflows/cleanup-deployments.md) |

---

## Composite actions

Actions can be used individually inside your own workflow steps:

```yaml
steps:
  - uses: KevinDeBenedetti/github-workflows/.github/actions/setup-node@main
    with:
      node-version: '24'
```

| Action                                                              | Description                                                                                      |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| [`setup-node`](actions/setup-node.md)                               | Install Node.js + pnpm/bun with cache                                                            |
| [`setup-python`](actions/setup-python.md)                           | Install Python + uv with cache                                                                   |
| [`shellcheck`](actions/shellcheck.md)                               | Run ShellCheck on all `.sh` files                                                                |
| [`bats`](actions/bats.md)                                           | Run Bats shell unit tests                                                                        |
| [`detect-changes`](actions/detect-changes.md)                       | Output a JSON matrix of changed apps in a monorepo                                               |
| [`change-base`](actions/change-base.md)                             | Find the commit a push or pull request's change starts from                                      |
| [`secret-scan`](actions/secret-scan.md)                             | Scan the commits a run brings with Gitleaks, with the config of a trusted commit                 |
| [`actionlint`](actions/actionlint.md)                               | Validate GitHub Actions workflow files                                                           |
| [`kubeconform`](actions/kubeconform.md)                             | Validate Kubernetes manifests                                                                    |
| [`tflint`](actions/tflint.md)                                       | Lint a Terraform module with tflint                                                              |
| [`config-scan`](actions/config-scan.md)                             | Scan infrastructure-as-code files for misconfigurations with Trivy                               |
| [`image-scan`](actions/image-scan.md)                               | Scan a container image for known vulnerabilities with Trivy                                      |
| [`osv-scan`](actions/osv-scan.md)                                   | Audit the dependencies of every lockfile with OSV-Scanner                                        |
| [`check-commit-msg`](actions/check-commit-msg.md)                   | Conventional Commits on commit messages (CI + commit-msg hook)                                   |
| [`setup-claude-code`](actions/setup-claude-code.md)                 | Install the Claude Code CLI, pinned and checked against a SHA-256                                |
| [`install-tool`](actions/install-tool.md)                           | Install one of the tools the actions download, pinned and checked (internal)                     |
| [`setup-promtool`](actions/setup-promtool.md)                       | Install promtool and yq, checked against their releases' SHA-256 lists (internal)                |
| [`pr-description`](actions/pr-description.md)                       | Write the PR description with Claude Code into a managed block of the PR body                    |
| [`check-docs-links`](actions/check-docs-links.md)                   | Check for broken links in docs                                                                   |
| [`check-docs-external-links`](actions/check-docs-external-links.md) | Check the `http(s)` links of changed docs pages with lychee                                      |
| [`check-vitepress-md`](actions/check-vitepress-md.md)               | Validate VitePress markdown                                                                      |
| [`notify-deployment`](actions/notify-deployment.md)                 | Post a deployment status notification                                                            |
| [`check-bot-commits`](actions/check-bot-commits.md)                 | Fail a pull request that brings commits of bots outside an allow-list                            |
| [`cleanup-runs`](actions/cleanup-runs.md)                           | Delete the old workflow runs of the repository, keeping the recent ones                          |
| [`cleanup-deployments`](actions/cleanup-deployments.md)             | Delete the old deployment records of the repository, keeping the recent ones of each environment |
| [`propagate-release`](actions/propagate-release.md)                 | Open a pull request in each consumer repository that moves its pins to a release                 |
| [`move-release-aliases`](actions/move-release-aliases.md)           | Move the `v<major>` (and `v0.<minor>`) alias tags to a release                                   |
| [`notify-release-reviewers`](actions/notify-release-reviewers.md)   | Request a review on the release PR from each listed user, once per user and PR                   |
| [`image-tags`](actions/image-tags.md)                               | Image name, tags and layer-cache reference of a container build                                  |

---

## Examples

Complete ready-to-use caller files live in [`examples/`](https://github.com/KevinDeBenedetti/github-workflows/tree/main/examples):

| File | Stack |
|---|---|
| `next.yml` | Next.js |
| `nuxt.yml` | Nuxt |
| `vue-react.yml` | Vue / React (Vite) |
| `fastapi.yml` | FastAPI (Python) |
| `monorepo.yml` | Monorepo with change detection |
| `pr-description.yml` | PR descriptions written by Claude Code |
| `cleanup-ghcr.yml` | Weekly GHCR retention |
| `cleanup-runs.yml` | Weekly workflow-run retention |
| `cleanup-deployments.yml` | Weekly deployment-record retention |
