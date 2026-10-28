---
title: '`cleanup-ghcr` workflow'
---

# `cleanup-ghcr` workflow

Deletes the old versions of the container images a repository publishes to GHCR,
on a schedule, with one retention policy for every repository. Release tags,
moving tags and recent images are never deleted.

## Usage

```yaml
# .github/workflows/cleanup-ghcr.yml  (in your repo)
name: Cleanup GHCR

on:
  schedule:
    - cron: "23 4 * * 1"  # Mondays, 04:23 UTC
  workflow_dispatch:

permissions: {}

jobs:
  cleanup:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cleanup-ghcr.yml@main
    permissions:
      packages: write
    with:
      packages: my-app              # default: the repository name
      cache-packages: my-app-cache  # layer cache of cd-buildkit / cd-kaniko
      dry-run: true
```

Start in dry-run: run the workflow once by hand from the Actions tab, read what the
log says it would delete, then remove the `dry-run` line so the weekly run deletes.

## Retention policy

The policy is set once, in this workflow, for every caller:

| Packages         | Kept                                                                                                                        | Deleted                                  |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| `packages`       | tags matching `exclude-tags`, every image younger than `older-than`, then the `keep-n-tagged` most recent older tagged ones | the other tagged images, untagged images |
| `cache-packages` | the `buildcache` tag, every version younger than `older-than`                                                               | every other version                      |

- The default `exclude-tags` keeps the release tags (`v1.2.3`, `1.2`) and the
  moving tags `latest`, `stable`, `main` and `dev`, so a deployed release is never
  deleted. Any tag that contains a dot is kept.
- An image deployed through a `sha-*` tag stays while it is younger than
  `older-than` or among the `keep-n-tagged` most recent older images.
- Deleting an image also deletes its children: the platform images of a
  multi-architecture image, its provenance and SBOM attestations, and referrers
  such as GitHub artifact attestations.
- `cache-packages` targets the registry layer caches written by
  [`cd-buildkit`](./cd-buildkit.md) and [`cd-kaniko`](./cd-kaniko.md), named
  `<image>-cache`. BuildKit reads only `buildcache`; Kaniko's per-layer cache
  images and the cache manifests that `buildcache` replaced are deleted once older
  than `older-than`.

## Inputs

| Input            | Type    | Default                           | Description                                                          |
| ---------------- | ------- | --------------------------------- | -------------------------------------------------------------------- |
| `packages`       | string  | the repository name               | Comma-separated image packages, as named in `ghcr.io/<owner>/<name>` |
| `cache-packages` | string  | `''`                              | Comma-separated layer-cache packages; empty skips the cache cleanup  |
| `exclude-tags`   | string  | `'latest,stable,main,dev,v*,*.*'` | Comma-separated tags never deleted, with `*` wildcards               |
| `older-than`     | string  | `30 days`                         | Only versions older than this are touched (`8 weeks`, `6 months`…)   |
| `keep-n-tagged`  | number  | `10`                              | Most recent tagged images kept among those older than `older-than`   |
| `dry-run`        | boolean | `false`                           | Log what would be deleted, delete nothing                            |
| `runner`         | string  | `'"ubuntu-latest"'`               | Runner labels as JSON                                                |

`packages` defaults to the repository name, the name [`cd-docker`](./cd-docker.md),
[`cd-buildkit`](./cd-buildkit.md) and [`cd-kaniko`](./cd-kaniko.md) give the image
when their `image-name` input is empty. Package names are lowercased.

## Permissions

- The calling job grants `packages: write`, and the workflow deletes with the
  caller's `GITHUB_TOKEN`: no personal access token and no GitHub App.
- A package published by a workflow of a repository gives that repository the
  Admin role, which can delete versions. For a package published another way, add
  the repository under the package's **Manage Actions access** with the Admin role.

## Notes

- Call it from the repository that publishes the packages, and list only packages
  that already exist in GHCR. Add a `-cache` package once a first build created it.
- The deletions go through
  [`dataaxiom/ghcr-cleanup-action`](https://github.com/dataaxiom/ghcr-cleanup-action),
  pinned by commit SHA. Never use `actions/delete-package-versions` on images built
  with provenance, SBOM or several platforms: it deletes the untagged children that
  tagged images still reference, which breaks every image. It only suits
  single-manifest packages such as Helm charts.
- One run at a time per repository: the cleanup action is not safe to run twice at
  once against the same package.
- A deleted version can be restored for 30 days, from the package settings on
  GitHub.
