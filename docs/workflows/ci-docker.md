---
title: CI — Docker
---

# CI — Docker

Builds a Docker image with **Docker Buildx** and pushes nothing: the build check of a
pull request. The job needs `contents: read` only, so it also runs on a fork's pull
request. [`cd-docker`](./cd-docker.md) builds the same image and pushes it.

## Usage

```yaml
jobs:
  image:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-docker.yml@v0.57.0 # x-release-please-version
    permissions:
      contents: read
    with:
      image-name: my-api
      context: apps/api
```

## Inputs

| Input             | Type    | Default            | Description                                                                           |
| ----------------- | ------- | ------------------ | ------------------------------------------------------------------------------------- |
| `image-name`      | string  | `''`               | Image name (e.g. `my-api`). Defaults to the repository name.                          |
| `context`         | string  | `'.'`              | Docker build context (e.g. `apps/api`)                                                |
| `dockerfile`      | string  | `Dockerfile`       | Path to the Dockerfile, relative to `context`                                         |
| `platforms`       | string  | `linux/amd64`      | Comma-separated target platforms                                                      |
| `target`          | string  | `''`               | Build target stage (e.g. `dev`, `prod`)                                               |
| `build-args`      | string  | `''`               | List of Docker build-args (one per line, `KEY=VALUE`). **Never secrets.**             |
| `run-image-scan`  | boolean | `false`            | Scan the image for known vulnerabilities (Trivy)                                      |
| `image-scan-fail-on` | string | `critical`      | Lowest severity that fails the image scan: `low`, `medium`, `high` or `critical`      |
| `runner`          | string  | `'"ubuntu-26.04"'` | Runner labels as JSON: a Linux VM runner with Docker, GitHub's or Ubicloud's          |
| `timeout-minutes` | number  | `30`               | Minutes before the build job is cancelled (GitHub's default is 360)                   |

## Secrets

| Secret          | Required | Description                                                                                              |
| --------------- | -------- | -------------------------------------------------------------------------------------------------------- |
| `BUILD_SECRETS` | No       | BuildKit secrets, one `id=value` per line, read in the Dockerfile with `RUN --mount=type=secret,id=<id>` |

## Notes

- Nothing is pushed: no registry login, no deployment record, no SBOM, provenance or attestation.
- `run-image-scan: true` builds the image for the runner's platform, loads it and scans it with the [`image-scan`](../actions/image-scan.md) action: a vulnerability at `image-scan-fail-on` or above fails the job, with the findings in the job summary.
- The tags and the OCI labels are computed by [`image-tags`](../actions/image-tags.md) as in `cd-docker`, so a name or a label the build refuses fails here.
- Layer cache: the GitHub Actions cache (`type=gha`), under the scope `cd-docker` uses for the same `context` and `target`. A cache export the token cannot write does not fail the build.
- `platforms` defaults to the runner's own architecture. QEMU is registered only when it names something else.
- A fork's pull request gets no secret: a Dockerfile that mounts one from `BUILD_SECRETS` must build without it, or the check is limited to pull requests of the repository.
