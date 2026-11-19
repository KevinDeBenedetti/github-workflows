---
title: Action — buildkit-build
---

# Action — buildkit-build

Builds and pushes an image with **rootless BuildKit** (`buildctl-daemonless.sh`) from the repository's git context at the triggering commit. It is the build step of [`cd-buildkit`](../workflows/cd-buildkit.md)'s cluster path, and runs inside the `moby/buildkit` rootless image: POSIX `sh`, no checkout, no JavaScript. Take the tags, cache reference and labels from [`image-tags`](./image-tags.md).

## Usage

```yaml
jobs:
  build:
    runs-on: <image-build scale set>
    container:
      image: moby/buildkit:v0.34.1-rootless
    permissions:
      contents: read   # BuildKit clones the git context with the token
      packages: write  # push the image and the layer cache
    steps:
      - id: build
        uses: KevinDeBenedetti/github-workflows/.github/actions/buildkit-build@main
        with:
          names: ${{ needs.tags.outputs.names }}
          cache: ${{ needs.tags.outputs.cache }}
          labels: ${{ needs.tags.outputs.labels }}
```

## Inputs

| Input           | Default      | Description                                                                |
| --------------- | ------------ | -------------------------------------------------------------------------- |
| `names`         | —            | `image:tag` list, comma-separated (`image-tags` `names`)                   |
| `cache`         | —            | Registry layer-cache reference (`image-tags` `cache`)                      |
| `labels`        | `''`         | OCI labels, one `KEY=VALUE` per line (`image-tags` `labels`)               |
| `build-args`    | `''`         | Build args, one `KEY=VALUE` per line — never secrets                       |
| `build-secrets` | `''`         | BuildKit secrets, one `id=value` per line, read with `--mount=type=secret` |
| `target`        | `''`         | Dockerfile stage; empty builds the last one                                |
| `push`          | `'true'`     | `'true'` pushes the image                                                  |
| `provenance`    | `mode=max`   | SLSA provenance: `mode=max`, `mode=min` or `false`                         |
| `sbom`          | `'true'`     | `'true'` attaches an SBOM attestation                                      |
| `context`       | `.`          | Build context directory, relative to the repository root                   |
| `dockerfile`    | `Dockerfile` | Dockerfile path, relative to the context                                   |
| `registry`      | `ghcr.io`    | Registry host the token logs in to                                         |
| `token`         | job token    | Fetches the git context (`contents: read`) and pushes (`packages: write`)  |

## Outputs

| Output   | Description                                        |
| -------- | -------------------------------------------------- |
| `digest` | Image digest (`sha256:…`), from the build metadata |

## Notes

- The context is `<server>/<repository>.git#<sha>`, narrowed to `:<context>` when it is not the root.
- No credential reaches the command line: the registry auth goes into a `DOCKER_CONFIG` file, the token (BuildKit's `GIT_AUTH_TOKEN` secret) and each `build-secrets` value into secret files, all in an owner-only directory under `$TMPDIR` removed when the step ends.
- A `build-secrets` id outside `A-Z a-z 0-9 _ . -` fails the step before the build starts.
- Each `build-args` and `labels` line stays one argument: spaces and `*` are kept as written.
- Layer cache: imported from and exported to `cache` with `mode=max`; an export failure does not fail the build.
