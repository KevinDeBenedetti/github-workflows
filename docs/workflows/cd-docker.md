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
| `build-args` | string  | `''`                      | List of Docker build-args (one per line, `KEY=VALUE`)        |

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
- Requires `packages: write` permission (granted automatically via `GITHUB_TOKEN`).
