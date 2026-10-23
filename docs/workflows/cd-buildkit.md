# CD — BuildKit rootless

Builds and pushes a container image with **rootless BuildKit** on a self-hosted k3s runner, then pushes to **GHCR**.
Successor of [`cd-kaniko.yml`](cd-kaniko.md) (upstream Kaniko is archived): same inputs and tags, but the builder runs as a non-root user, and the workflow adds a `digest` output, build secrets, provenance and SBOM.

::: warning Experimental
Not yet validated on the cluster. It needs the cluster-side setup below; until then keep `cd-kaniko.yml`.
:::

## Usage

```yaml
jobs:
  build:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/cd-buildkit.yml@v0.27.0
    permissions:
      contents: read
      packages: write
    with:
      image-name: my-api
      context: apps/api
      version: ${{ needs.release.outputs.version }}
      tag-latest: true
      runner: '"k3s-portfolio"'
    secrets:
      BUILD_SECRETS: |
        npm_token=${{ secrets.NPM_TOKEN }}
```

## Inputs

| Input        | Type    | Default                                    | Description |
| ------------ | ------- | ------------------------------------------ | ----------- |
| `image-name` | string  | `''`                                       | Image name (e.g. `my-api`). Defaults to the repository name. |
| `context`    | string  | `'.'`                                      | Docker build context path (relative to repo root) |
| `dockerfile` | string  | `Dockerfile`                               | Dockerfile path relative to `context` |
| `push`       | boolean | `true`                                     | Push the image to the registry |
| `target`     | string  | `''`                                       | Build target stage (e.g. `dev`, `prod`) |
| `tag-latest` | boolean | `false`                                    | Also tag as `:latest` on the default branch |
| `version`    | string  | `''`                                       | Explicit version tag (e.g. `v1.2.3`); a `major.minor` tag is added when semver |
| `build-args` | string  | `''`                                       | Build args, one per line, `KEY=VALUE`. **Never secrets** — use `BUILD_SECRETS` |
| `provenance` | string  | `mode=max`                                 | SLSA provenance (`mode=max`, `mode=min`, `false`). `mode=max` records the build-args |
| `sbom`       | boolean | `true`                                     | Attach an SBOM attestation |
| `runner`     | string  | `'["self-hosted","linux","k3s","kaniko"]'` | Runner labels as JSON — `'"k3s-portfolio"'` (ARC scale set) or a label array |

## Secrets

| Secret          | Required | Description |
| --------------- | -------- | ----------- |
| `BUILD_SECRETS` | No       | One `id=value` per line, read in the Dockerfile with `RUN --mount=type=secret,id=<id>` |

## Outputs

| Output   | Description |
| -------- | ----------- |
| `image`  | Image name (without tag) |
| `digest` | Image digest |

## Cluster prerequisites

Rootless BuildKit creates its own user namespace and mounts inside it. The container runtime's default seccomp and AppArmor profiles forbid that, so the workflow pod must run with ([BuildKit rootless docs](https://github.com/moby/buildkit/blob/master/docs/rootless.md), [Kubernetes example](https://github.com/moby/buildkit/tree/master/examples/kubernetes)):

```yaml
# ARC containerMode hook template, merged into the "$job" container
spec:
  containers:
    - name: "$job"
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        seccompProfile:
          type: Unconfined
        appArmorProfile:
          type: Unconfined
```

- **Pod Security**: `seccompProfile: Unconfined` and AppArmor `Unconfined` are refused by the **`baseline`** level. A namespace enforcing `baseline` (the k3s `ci` namespace does) rejects the pod — run the build scale set in a dedicated namespace whose level allows it, rather than relaxing the namespace shared by every runner.
- Use a **dedicated hook template** referenced only by the scale set(s) that build images, so the other `container:` jobs keep the default profiles.
- The trade-off: Kaniko ran as **root** under the default profiles; rootless BuildKit runs as an **unprivileged user** in its own user namespace, without the default seccomp/AppArmor filters.
- The workflow sets `BUILDKITD_FLAGS=--oci-worker-no-process-sandbox` (Kubernetes has no `systempaths=unconfined`): `RUN` steps share the builder's PID namespace, as in BuildKit's own Kubernetes examples.

## Notes

- Like the Kaniko image, the BuildKit image cannot run JavaScript actions: BuildKit fetches the source itself from a git context (`<repo>.git#<sha>:<context>`) with the job token, passed as the `GIT_AUTH_TOKEN` build secret.
- Registry credentials and secrets are written to a `0700` temporary directory removed at the end of the step.
- Layer cache: `<image>-cache:buildcache` on GHCR (`mode=max`; export failures don't fail the build).
- Single architecture (native cluster arch).
