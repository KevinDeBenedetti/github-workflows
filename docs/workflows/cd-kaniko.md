# CD — Kaniko

Builds and pushes a container image with **Kaniko** on a self-hosted k3s runner, then pushes to **GHCR**.
A drop-in replacement for `cd-docker.yml` for builds running inside the cluster — single-arch, no Docker daemon, no JS actions.

## Usage

```yaml
jobs:
  build:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-kaniko.yml@main
    with:
      image-name: my-api
      context: apps/api
      version: ${{ needs.release.outputs.version }}
      tag-latest: true
      runner: '"k3s-portfolio"'
```

## Inputs

| Input        | Type    | Default                                          | Description                                                              |
| ------------ | ------- | ------------------------------------------------ | ------------------------------------------------------------------------ |
| `image-name` | string  | `''`                                             | Image name (e.g. `my-api`). Defaults to the repository name             |
| `context`    | string  | `'.'`                                            | Docker build context path (relative to repo root)                        |
| `dockerfile` | string  | `Dockerfile`                                     | Dockerfile path relative to `context`                                    |
| `push`       | boolean | `true`                                           | Push the image to the registry (`false` adds `--no-push`)                |
| `target`     | string  | `''`                                             | Build target stage (e.g. `dev`, `prod`)                                  |
| `tag-latest` | boolean | `false`                                          | Also tag as `:latest` on the default branch                              |
| `version`    | string  | `''`                                             | Explicit version tag (e.g. `v1.2.3`); a `major.minor` tag is added when semver |
| `build-args` | string  | `''`                                             | Build args, one per line, `KEY=VALUE`                                    |
| `runner`     | string  | `'["self-hosted","linux","k3s","kaniko"]'`       | Runner labels as JSON — `'"k3s-portfolio"'` (ARC scale set) or a label array |

## Outputs

| Output  | Description       |
| ------- | ----------------- |
| `image` | Primary image tag (`ghcr.io/<owner>/<name>`) |

## Steps

1. Set image name (normalised to lowercase `ghcr.io/<owner>/<name>`)
2. GHCR auth for Kaniko (writes `/kaniko/.docker/config.json` from `GITHUB_TOKEN`)
3. Compute tags in POSIX sh (`sha-<short>`, branch, `pr-<n>`, `version`, `major.minor`, `latest`)
4. Build and push with Kaniko (`/kaniko/executor` over a git build context, with `--cache`)
5. Job summary (image, context, SHA, and all tags)

## Notes

- The job runs **inside** the official Kaniko executor image (`gcr.io/kaniko-project/executor:*-debug`), so the ARC runner scale set must be deployed with `containerMode: kubernetes` — Kaniko needs root in a disposable container to unpack base-image layers.
- The debug image is busybox-only (no glibc), so it **cannot** run JS actions like `actions/checkout` or `docker/metadata-action`. Kaniko fetches the source itself via its git build context, and tags are computed in `sh`.
- GHCR auth uses the job's `GITHUB_TOKEN` (`permissions: packages: write`) — no registry secret is needed. The same token clones the source (`GIT_USERNAME`/`GIT_PASSWORD`).
- Single architecture only (native cluster arch — `linux/amd64`). No QEMU / multi-platform builds.
- No GHA layer cache — Kaniko uses `--cache-repo` (`<image>-cache`) on GHCR instead.
- Source is cloned by Kaniko from a git context, so the job runs on **push** events; PR refs (`refs/pull/N/merge`) are not fetchable this way.
- No `digest` output — Kaniko does not expose it the way `docker/build-push-action` does.

## Secrets

None. The job uses the built-in `GITHUB_TOKEN` (requires `packages: write`).
