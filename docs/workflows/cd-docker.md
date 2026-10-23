# Deploy — Docker

Builds a multi-platform Docker image and pushes it to **GitHub Container Registry (GHCR)**.

## Usage

```yaml
jobs:
  docker:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-docker.yml@main
    with:
      image-name: my-api
      platforms: linux/amd64,linux/arm64
```

## Inputs

| Input        | Type    | Default                   | Description                                                  |
| ------------ | ------- | ------------------------- | ------------------------------------------------------------ |
| `image-name` | string  | `''`                      | Image name (e.g. `my-api`). Defaults to the repository name. |
| `context`    | string  | `'.'`                     | Docker build context (e.g. `apps/api`)                       |
| `dockerfile` | string  | `Dockerfile`              | Path to the Dockerfile, relative to `context`                |
| `platforms`  | string  | `linux/amd64,linux/arm64` | Comma-separated target platforms                             |
| `push`       | boolean | `true`                    | Push image to GHCR                                           |
| `target`     | string  | `''`                      | Build target stage (e.g. `dev`, `prod`)                      |
| `tag-latest` | boolean | `false`                   | Also tag the image as `:latest` on the default branch        |
| `version`    | string  | `''`                      | Explicit version tag to apply (e.g. `v1.2.3`). When set, adds a `type=raw` tag with this value. |
| `build-args` | string  | `''`                      | List of Docker build-args (one per line, `KEY=VALUE`). **Never secrets** — see below. |
| `provenance` | string  | `mode=max`                | SLSA provenance attached by BuildKit (`mode=max`, `mode=min`, `false`) |
| `sbom`       | boolean | `true`                    | Attach an SBOM attestation to the image                      |
| `attest`     | boolean | `true`                    | Sign a GitHub artifact attestation for the pushed image (only when `push`) |

## Secrets

| Secret          | Required | Description |
| --------------- | -------- | ----------- |
| `BUILD_SECRETS` | No       | BuildKit secrets, one `id=value` per line, read in the Dockerfile with `RUN --mount=type=secret,id=<id>` |

## Outputs

| Output   | Description                        |
| -------- | ---------------------------------- |
| `image`  | Image tag(s) applied to the build (newline-separated) |
| `digest` | Image digest                       |

## Tags applied

| Event                               | Tag                            |
| ----------------------------------- | ------------------------------ |
| Branch push                         | `<branch-name>`                |
| Pull request                        | `pr-<number>`                  |
| Semver tag                          | `<version>`, `<major>.<minor>` |
| Any commit                          | `sha-<short-sha>`              |
| Default branch + `tag-latest: true` | `latest`                       |

## Notes

- Uses `docker/metadata-action` for automatic tag and label generation.
- Build cache is scoped per `context` using GitHub Actions cache (`type=gha`).
- The job runs in the `production` environment on `main`, otherwise `preview`.
- **Caller permissions** — a reusable workflow gets at most what its caller grants, and GitHub refuses the run if a job asks for more (even when `attest` is false). Grant on the calling job:
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
