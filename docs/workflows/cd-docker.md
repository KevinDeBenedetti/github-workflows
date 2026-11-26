---
title: Deploy — Docker
---

# Deploy — Docker

Builds a Docker image with **Docker Buildx** and pushes it to **GitHub Container Registry (GHCR)**, for one or several platforms, with provenance, an SBOM and a signed attestation.

## Usage

```yaml
jobs:
  docker:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-docker.yml@v0.56.2 # x-release-please-version
    with:
      image-name: my-api
      platforms: linux/amd64,linux/arm64
```

One platform, on an Ubicloud runner, with the layer cache in GHCR and no deployment record:

```yaml
jobs:
  docker:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-docker.yml@v0.56.2 # x-release-please-version
    with:
      image-name: my-api
      platforms: linux/amd64
      runner: '"ubicloud-standard-2"'
      registry-cache: true
      deployment: false
```

## Inputs

| Input             | Type    | Default                   | Description                                                                                              |
| ----------------- | ------- | ------------------------- | -------------------------------------------------------------------------------------------------------- |
| `image-name`      | string  | `''`                      | Image name (e.g. `my-api`). Defaults to the repository name.                                             |
| `context`         | string  | `'.'`                     | Docker build context (e.g. `apps/api`)                                                                   |
| `dockerfile`      | string  | `Dockerfile`              | Path to the Dockerfile, relative to `context`                                                            |
| `platforms`       | string  | `linux/amd64,linux/arm64` | Comma-separated target platforms                                                                         |
| `push`            | boolean | `true`                    | Push image to GHCR                                                                                       |
| `target`          | string  | `''`                      | Build target stage (e.g. `dev`, `prod`)                                                                  |
| `tag-latest`      | boolean | `false`                   | Also tag the image as `:latest` on the default branch                                                    |
| `version`         | string  | `''`                      | Explicit version tag to apply (e.g. `v1.2.3`), plus its `major.minor` alias for a final release          |
| `build-args`      | string  | `''`                      | List of Docker build-args (one per line, `KEY=VALUE`). **Never secrets** — see below.                    |
| `provenance`      | string  | `mode=max`                | SLSA provenance attached by BuildKit (`mode=max`, `mode=min`, `false`)                                   |
| `sbom`            | boolean | `true`                    | Attach an SBOM attestation to the image                                                                  |
| `attest`          | boolean | `true`                    | Sign a GitHub artifact attestation for the pushed image (only when `push`)                               |
| `run-image-scan`  | boolean | `false`                   | Scan the image for known vulnerabilities (Trivy) before it is pushed                                     |
| `image-scan-fail-on` | string | `critical`             | Lowest severity that fails the image scan: `low`, `medium`, `high` or `critical`                         |
| `registry-cache`  | boolean | `false`                   | Keep the layer cache in GHCR (`<image>-cache:buildcache`) instead of the GitHub Actions cache            |
| `deployment`      | boolean | `true`                    | Run the build in the `production` or `preview` environment, which records a deployment                   |
| `runner`          | string  | `'"ubuntu-26.04"'`        | Runner labels as JSON: a Linux VM runner with Docker, GitHub's or Ubicloud's                             |
| `timeout-minutes` | number  | `60`                      | Minutes before the build job is cancelled (GitHub's default is 360) — raise it for a slow emulated build |

## Secrets

| Secret          | Required | Description                                                                                              |
| --------------- | -------- | -------------------------------------------------------------------------------------------------------- |
| `BUILD_SECRETS` | No       | BuildKit secrets, one `id=value` per line, read in the Dockerfile with `RUN --mount=type=secret,id=<id>` |

## Outputs

| Output       | Description                                           |
| ------------ | ----------------------------------------------------- |
| `image`      | Image tag(s) applied to the build (newline-separated) |
| `image-name` | Image name without a tag (`ghcr.io/<owner>/<name>`)   |
| `digest`     | Image digest                                          |

## Tags applied

The [`image-tags`](../actions/image-tags.md) action computes them:

| Event                               | Tag                                                              |
| ----------------------------------- | ---------------------------------------------------------------- |
| Branch push                         | `<branch-name>`                                                  |
| Pull request                        | `pr-<number>`                                                    |
| Release tag push (`v1.2.3`)         | `<version>`, `<major>.<minor>` (a pre-release: `<version>` only) |
| `version` set                       | the version, `<major>.<minor>` for a final release               |
| Any commit                          | `sha-<short-sha>`                                                |
| Default branch + `tag-latest: true` | `latest`                                                         |

## Notes

- The tags and the OCI labels come from [`image-tags`](../actions/image-tags.md); `docker/metadata-action` only turns the tags into full image names.
- Layer cache: by default the GitHub Actions cache (`type=gha`), scoped per `context` and `target`. With `registry-cache: true` it is the image `<image>-cache:buildcache` in GHCR (`mode=max`; a failed export does not fail the build): it is not evicted like the Actions cache, and the job then logs in to GHCR even when `push` is false. [`cleanup-ghcr`](./cleanup-ghcr.md) prunes it with `cache-packages`.
- `runner` takes any Linux VM runner with a Docker daemon. QEMU emulates every platform other than `linux/amd64`: to build one platform natively, name it in `platforms` and pick a runner of that architecture.
- QEMU is registered only when `platforms` names something other than `linux/amd64`, the runner's own architecture. An `arm64` image built this way runs under emulation, several times slower than a native build: for a large image, build each platform on its own runner (GitHub's `ubuntu-26.04-arm` label for the arm64 half) and merge the manifests, as Docker documents, or drop `linux/arm64` from `platforms` when nothing deploys on it.
- `timeout-minutes` cuts off a build stuck on a pull or an emulated step: without it the job holds the runner (and bills the minutes) for up to 6 hours.
- Each build adds a `sha-*` tag, and each platform image and attestation is an untagged version in GHCR: [`cleanup-ghcr`](./cleanup-ghcr.md) deletes the old ones on a schedule without breaking multi-arch images.
- With a push, the job runs in the `production` environment on `main`, otherwise `preview`, and GitHub records a deployment. `deployment: false` runs it in no environment.
- `run-image-scan: true` builds the image for the runner's platform, loads it and scans it with the [`image-scan`](../actions/image-scan.md) action before the push: a vulnerability at `image-scan-fail-on` or above fails the job, and nothing is pushed or attested. The findings are in the job summary; the vulnerability database is cached for the day. The other platforms of a multi-platform build are not scanned. A vulnerability counts whether a fix exists or not: silence one in a `.trivyignore` file at the root of the repository.
- **Caller permissions** — a reusable workflow gets at most what its caller grants, and GitHub refuses the run if a job asks for more (even when `attest` or `push` is false). To build an image on a pull request without these scopes, a fork's included, call [`ci-docker`](./ci-docker.md) instead. Grant on the calling job:
  ```yaml
  permissions:
    contents: read
    packages: write
    deployments: write
    id-token: write      # attestation signing
    attestations: write
  ```
- **Never pass secrets in `build-args`**: they stay in the image history, and `provenance: mode=max` records their values in an attestation anyone pulling the image can read. Use `BUILD_SECRETS` (secret mounts) instead.
- The attestation is signed in a separate job, so the build step (which runs the Dockerfile) never holds an OIDC token. Verify an image with `gh attestation verify oci://ghcr.io/<owner>/<image>@<digest> --owner <owner>`.

## Coming from `cd-buildkit`

`cd-buildkit.yml` was removed: this workflow builds the same image. Change the
call as follows:

```yaml
jobs:
  build:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-docker.yml@v0.56.2 # x-release-please-version
    permissions:
      contents: read
      packages: write
      deployments: write   # declared by the build job, unused with deployment: false
      id-token: write      # attestation signing (or unused with attest: false)
      attestations: write
    with:
      platforms: linux/amd64   # cd-buildkit built the runner's platform only
      registry-cache: true     # the cache cd-buildkit used: <image>-cache:buildcache
      deployment: false        # cd-buildkit recorded no deployment
      attest: false            # cd-buildkit signed no attestation; drop to get one
      # image-name, context, dockerfile, target, tag-latest, version, build-args,
      # provenance, sbom, runner and timeout-minutes keep their names and values.
```

The `image` output is now the list of full image names with their tags; the bare
image name `cd-buildkit` returned there is the `image-name` output. `digest` is
unchanged. The job's check is named
`Docker build & push (<context>)`.
