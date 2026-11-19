---
title: CD — BuildKit
---

# CD — BuildKit

Builds a container image with **BuildKit**, driven by **Docker Buildx**, and pushes it to **GHCR**. The image is built for the runner's native platform, from a checkout of the triggering commit, with provenance, an SBOM and a registry layer cache. For a multi-platform image, use [`cd-docker`](./cd-docker.md).

## Usage

```yaml
jobs:
  build:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-buildkit.yml@main
    permissions:
      contents: read
      packages: write
    with:
      image-name: my-api
      context: apps/api
      version: ${{ needs.release.outputs.version }}
      tag-latest: true
    secrets:
      BUILD_SECRETS: |
        npm_token=${{ secrets.NPM_TOKEN }}
```

## Runners

The `runner` input takes any Linux VM runner with a Docker daemon: GitHub's `ubuntu-…` labels, e.g. `'"ubuntu-26.04"'` (the default), or Ubicloud's `ubicloud-…` labels, e.g. `'"ubicloud-standard-2"'`. Nothing has to be set up on either.

The image is built for the runner's native platform: use an x86_64 runner for an x86_64 host. One repository variable can move every job, image builds included:

```yaml
    with:
      runner: ${{ vars.CI_RUNNER || '"ubuntu-26.04"' }}
```

## Inputs

| Input        | Type    | Default                                    | Description                                                                          |
| ------------ | ------- | ------------------------------------------ | ------------------------------------------------------------------------------------ |
| `image-name` | string  | `''`                                       | Image name (e.g. `my-api`). Defaults to the repository name.                         |
| `context`    | string  | `'.'`                                      | Docker build context path (relative to repo root)                                    |
| `dockerfile` | string  | `Dockerfile`                               | Dockerfile path relative to `context`                                                |
| `push`       | boolean | `true`                                     | Push the image to the registry                                                       |
| `target`     | string  | `''`                                       | Build target stage (e.g. `dev`, `prod`)                                              |
| `tag-latest` | boolean | `false`                                    | Also tag as `:latest` on the default branch                                          |
| `version`    | string  | `''`                                       | Version tag (e.g. `v1.2.3`); semver adds a `major.minor` alias, a pre-release none   |
| `build-args` | string  | `''`                                       | Build args, one per line, `KEY=VALUE`. **Never secrets** — use `BUILD_SECRETS`       |
| `provenance` | string  | `mode=max`                                 | SLSA provenance (`mode=max`, `mode=min`, `false`). `mode=max` records the build-args |
| `sbom`       | boolean | `true`                                     | Attach an SBOM attestation                                                           |
| `runner`     | string  | `'"ubuntu-26.04"'`                         | Runner labels as JSON (see [Runners](#runners))                                      |
| `timeout-minutes` | number | `60`                                  | Minutes before the build job is cancelled (GitHub's default is 360)                  |

## Secrets

| Secret          | Required | Description                                                                            |
| --------------- | -------- | -------------------------------------------------------------------------------------- |
| `BUILD_SECRETS` | No       | One `id=value` per line, read in the Dockerfile with `RUN --mount=type=secret,id=<id>` |

## Outputs

| Output   | Description              |
| -------- | ------------------------ |
| `image`  | Image name (without tag) |
| `digest` | Image digest             |

## Notes

- The source comes from `actions/checkout` of the triggering commit, and the job logs in to GHCR even when `push` is false, since the layer cache lives there.
- Tags: the [`image-tags`](../actions/image-tags.md) action computes the image name, tags, cache reference and OCI labels, so this workflow and [`cd-docker`](./cd-docker.md) tag alike. A push of a release tag `v1.2.3` adds `1.2.3` and `1.2`.
- Layer cache: `<image>-cache:buildcache` on GHCR (`mode=max`; export failures don't fail the build).
- Each build leaves new versions in GHCR: the tagged image index with its untagged image and attestations, and the replaced cache manifest. [`cleanup-ghcr`](./cleanup-ghcr.md) deletes the old ones on a schedule.
- Single architecture: the runner's native platform.
