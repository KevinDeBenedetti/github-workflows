# github-workflows

Reusable GitHub Actions workflows and composite actions for Node.js and Python projects.

All workflows are designed as `workflow_call` targets — they expose typed inputs, secrets and outputs so callers stay minimal and consistent.

---

## Structure

```
.github/
  actions/
    detect-changes/   # Monorepo changed-app detection
    setup-node/       # Node.js + pnpm/bun setup with cache
    setup-python/     # Python + uv setup with cache
  workflows/
    ci-node.yml       # Lint → typecheck → test → build (Node)
    ci-python.yml     # Lint → format → typecheck → test (Python)
    deploy-docker.yml # Build & push image to GHCR
    deploy-pages.yml  # Build & deploy to GitHub Pages
    deploy-vercel.yml # Deploy preview or production to Vercel
    release.yml       # Automated releases via release-please
    security.yml      # Dependency audit + CodeQL + secret scanning
examples/             # Ready-to-copy caller workflow examples
```

---

## Reusable Workflows

### `ci-node.yml` — CI for Node.js

Runs lint, typecheck, tests, and build. Auto-detects **pnpm** or **bun** from the lockfile.

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-node.yml@main
    with:
      node-version: '20'        # default: '20'
      working-directory: '.'    # default: '.'
      package-manager: auto     # 'pnpm' | 'bun' | 'auto' (default)
      framework: auto           # 'next' | 'nuxt' | 'vite' | 'auto'
      run-lint: true
      run-typecheck: true
      run-test: true
      run-build: true
      upload-build: false       # upload artifact when true
      build-artifact-name: build
```

---

### `ci-python.yml` — CI for Python

Runs ruff lint/format, ty type-checking, and pytest. Uses **uv** for dependency management.

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-python.yml@main
    with:
      python-version: '3.12'    # default: '3.12'
      working-directory: '.'
      run-lint: true            # ruff check
      run-format: true          # ruff format --check
      run-typecheck: true       # ty check
      run-test: true            # pytest
      run-coverage: false
      coverage-fail-under: 80
```

---

### `deploy-docker.yml` — Build & push to GHCR

Builds a multi-platform Docker image and pushes it to GitHub Container Registry.

```yaml
jobs:
  docker:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/deploy-docker.yml@main
    with:
      image-name: my-api         # defaults to repo name
      context: '.'
      dockerfile: Dockerfile
      platforms: linux/amd64,linux/arm64
      push: true
      tag-latest: false
```

**Outputs:** `image` (full image reference), `digest`.

---

### `deploy-pages.yml` — Deploy to GitHub Pages

Builds a static site and deploys it via the official Pages action.

```yaml
jobs:
  pages:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/deploy-pages.yml@main
    with:
      working-directory: '.'
      node-version: '20'
      build-command: 'pnpm build'
      output-directory: dist
```

**Outputs:** `page-url`.

---

### `deploy-vercel.yml` — Deploy to Vercel

Deploys a preview or production build through the Vercel CLI.

```yaml
jobs:
  deploy:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/deploy-vercel.yml@main
    with:
      environment: preview       # 'preview' | 'production'
      working-directory: '.'
      node-version: '20'
    secrets:
      VERCEL_TOKEN: ${{ secrets.VERCEL_TOKEN }}
      VERCEL_ORG_ID: ${{ secrets.VERCEL_ORG_ID }}
      VERCEL_PROJECT_ID: ${{ secrets.VERCEL_PROJECT_ID }}
```

**Outputs:** `deployment-url`.

---

### `release.yml` — Automated releases

Creates release PRs and GitHub Releases using [release-please](https://github.com/googleapis/release-please-action).

```yaml
jobs:
  release:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/release.yml@main
    with:
      release-type: node         # 'node' | 'python' | 'simple' | …
      # Or use a config file:
      config-file: release-please-config.json
      manifest-file: .release-please-manifest.json
    secrets:
      RELEASE_TOKEN: ${{ secrets.RELEASE_TOKEN }}
```

Also moves the `v<major>` tag alias after each release.

**Outputs:** `released` (boolean), `tag` (e.g. `v1.2.3`).

---

### `security.yml` — Security audit

Runs dependency audits, secret scanning, and CodeQL SAST.

```yaml
jobs:
  security:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/security.yml@main
    with:
      run-node-audit: true
      node-working-directory: '.'
      run-python-audit: false
      python-working-directory: '.'
      run-codeql: true
      codeql-languages: '["javascript","typescript"]'
```

---

## Composite Actions

### `setup-node`

Installs Node.js and the right package manager (pnpm or bun) with cache restoration.

```yaml
- uses: KevinDeBenedetti/github-workflows/.github/actions/setup-node@main
  with:
    node-version: '20'
    working-directory: '.'
    package-manager: auto   # auto-detects bun.lock / bun.lockb → bun, else pnpm
    install: 'true'
```

**Outputs:** `package-manager`, `cache-hit`.

---

### `setup-python`

Installs Python and uv, then runs `uv sync --frozen`.

```yaml
- uses: KevinDeBenedetti/github-workflows/.github/actions/setup-python@main
  with:
    python-version: '3.12'
    working-directory: '.'
    install: 'true'
```

**Outputs:** `cache-hit`.

---

### `detect-changes`

Detects which subdirectories under `apps/` changed, outputting a JSON array for use in matrix jobs.

```yaml
- uses: KevinDeBenedetti/github-workflows/.github/actions/detect-changes@main
  id: changes
  with:
    apps-directory: apps
    base-ref: ''    # auto-resolves from PR base or HEAD~1

# Use output in a downstream job matrix:
# ${{ fromJson(steps.changes.outputs.changed-apps) }}
```

**Outputs:** `changed-apps` (JSON array), `has-changes`, `changed-api`, `changed-web`, `changed-client`.

---

## Examples

See [`examples/`](examples/) for ready-to-use caller workflows:

| File               | Stack                          |
| ------------------ | ------------------------------ |
| `ci-cd.pages.yml`  | Node.js + GitHub Pages         |
| `ci-cd.vercel.yml` | Node.js + Vercel               |
| `next.yml`         | Next.js                        |
| `nuxt.yml`         | Nuxt                           |
| `vue-react.yml`    | Vue / React (Vite)             |
| `fastapi.yml`      | FastAPI (Python)               |
| `monorepo.yml`     | Monorepo with change detection |
