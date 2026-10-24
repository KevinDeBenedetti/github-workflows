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

| Input        | Type    | Default                                    | Description                                                                          |
| ------------ | ------- | ------------------------------------------ | ------------------------------------------------------------------------------------ |
| `image-name` | string  | `''`                                       | Image name (e.g. `my-api`). Defaults to the repository name.                         |
| `context`    | string  | `'.'`                                      | Docker build context path (relative to repo root)                                    |
| `dockerfile` | string  | `Dockerfile`                               | Dockerfile path relative to `context`                                                |
| `push`       | boolean | `true`                                     | Push the image to the registry                                                       |
| `target`     | string  | `''`                                       | Build target stage (e.g. `dev`, `prod`)                                              |
| `tag-latest` | boolean | `false`                                    | Also tag as `:latest` on the default branch                                          |
| `version`    | string  | `''`                                       | Explicit version tag (e.g. `v1.2.3`); a `major.minor` tag is added when semver       |
| `build-args` | string  | `''`                                       | Build args, one per line, `KEY=VALUE`. **Never secrets** — use `BUILD_SECRETS`       |
| `provenance` | string  | `mode=max`                                 | SLSA provenance (`mode=max`, `mode=min`, `false`). `mode=max` records the build-args |
| `sbom`       | boolean | `true`                                     | Attach an SBOM attestation                                                           |
| `runner`     | string  | `'["self-hosted","linux","k3s","kaniko"]'` | Runner labels as JSON — `'"k3s-portfolio"'` (ARC scale set) or a label array         |

## Secrets

| Secret          | Required | Description                                                                            |
| --------------- | -------- | -------------------------------------------------------------------------------------- |
| `BUILD_SECRETS` | No       | One `id=value` per line, read in the Dockerfile with `RUN --mount=type=secret,id=<id>` |

## Outputs

| Output   | Description              |
| -------- | ------------------------ |
| `image`  | Image name (without tag) |
| `digest` | Image digest             |

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
        # newuidmap (subuid mapping) is setuid: no_new_privs breaks it.
        allowPrivilegeEscalation: true
        seccompProfile:
          type: Unconfined
        appArmorProfile:
          type: Unconfined
```

- **Pod Security**: `seccompProfile: Unconfined` and AppArmor `Unconfined` are refused by the **`baseline`** level, so the namespace running the build pods must enforce **`privileged`**. User namespaces (`hostUsers: false`) do not avoid it: without the unconfined profiles, BuildKit would need `CAP_SYS_ADMIN`, which `baseline` refuses too. Run the build scale set in a dedicated namespace rather than relaxing the one shared by every runner.
- **Policy engines** (Kyverno, Gatekeeper…) that enforce `allowPrivilegeEscalation: false` or `capabilities.drop: [ALL]` reject the pod as well — dropping ALL removes the `CAP_SETUID` that `newuidmap` needs.
- Use a **dedicated hook template** referenced only by the scale set(s) that build images, so the other `container:` jobs keep the default profiles.
- The trade-off: Kaniko ran as **root** under the default profiles; rootless BuildKit runs as an **unprivileged user** in its own user namespace, without the default seccomp/AppArmor filters.
- The workflow sets `BUILDKITD_FLAGS=--oci-worker-no-process-sandbox` (Kubernetes has no `systempaths=unconfined`): `RUN` steps share the builder's PID namespace, as in BuildKit's own Kubernetes examples.

### Validate the cluster first

Before changing any namespace or scale set, run this throwaway Job. It builds a Dockerfile that installs a package and `chown`s to another UID — the subuid mapping real builds rely on — with exactly the settings above:

```yaml
# BuildKit rootless smoke test — checks that the cluster's nodes can run
# rootless BuildKit with the securityContext cd-buildkit.yml needs, BEFORE any
# change to the ci namespace or the ARC scale sets. Throwaway: delete the
# namespace afterwards (kubectl delete namespace buildkit-smoke).
apiVersion: v1
kind: Namespace
metadata:
  name: buildkit-smoke
  labels:
    # baseline refuses seccomp/AppArmor Unconfined — the very thing under test.
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/warn: baseline
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: buildkit-smoke
  namespace: buildkit-smoke
data:
  # What real image builds rely on: a package install (network, root-owned
  # files) and a chown to another UID — that needs the subuid range, i.e.
  # newuidmap, the step that breaks without allowPrivilegeEscalation.
  Dockerfile: |
    FROM alpine:3.22
    RUN apk add --no-cache git \
     && adduser -D -u 4242 app \
     && install -d -o app -g app /data \
     && stat -c 'owner of /data: %u:%g' /data
---
apiVersion: batch/v1
kind: Job
metadata:
  name: buildkit-smoke
  namespace: buildkit-smoke
spec:
  backoffLimit: 0
  activeDeadlineSeconds: 600
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: buildkit
          image: moby/buildkit:v0.34.1-rootless@sha256:f68752a5a94acfcdad2d07867b7075601a421638e17fc5f28efc1c814d0c4f89
          command: ["buildctl-daemonless.sh"]
          args:
            - build
            - --progress
            - plain
            - --frontend
            - dockerfile.v0
            - --local
            - context=/work
            - --local
            - dockerfile=/work
            - --output
            - type=image,name=buildkit-smoke:test,push=false
          env:
            # Same flag as cd-buildkit.yml (no systempaths=unconfined on k8s).
            - name: BUILDKITD_FLAGS
              value: --oci-worker-no-process-sandbox
          securityContext:
            runAsUser: 1000
            runAsGroup: 1000
            runAsNonRoot: true
            # newuidmap is setuid: no_new_privs would break the UID mapping.
            allowPrivilegeEscalation: true
            seccompProfile:
              type: Unconfined
            appArmorProfile:
              type: Unconfined
          resources:
            requests:
              cpu: 200m
              memory: 256Mi
            limits:
              cpu: "1"
              memory: 1Gi
          volumeMounts:
            - name: work
              mountPath: /work
              readOnly: true
            # One emptyDir (world-writable, exists from the start) per directory
            # rootless BuildKit writes to: the image's own copies were not
            # writable by UID 1000 in the pod, and rootlesskit does not create
            # its TMPDIR. A single emptyDir on ~/.local would hide these.
            - name: user-tmp
              mountPath: /home/user/.local/tmp          # TMPDIR (rootlesskit state)
            - name: buildkit-state
              mountPath: /home/user/.local/share/buildkit
            - name: user-runtime
              mountPath: /run/user/1000                 # XDG_RUNTIME_DIR
      volumes:
        - name: work
          configMap:
            name: buildkit-smoke
        - name: user-tmp
          emptyDir: {}
        - name: buildkit-state
          emptyDir: {}
        - name: user-runtime
          emptyDir: {}
```

```bash
kubectl apply -f buildkit-smoke-test.yaml
kubectl -n buildkit-smoke wait --for=condition=complete job/buildkit-smoke --timeout=10m
kubectl -n buildkit-smoke logs job/buildkit-smoke | tail -n 30
kubectl delete namespace buildkit-smoke
```

| Outcome                                                                      | Meaning                                                                                                                                                                                                                                  |
| ---------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Job completes, logs show `owner of /data: 4242:4242`                         | Rootless BuildKit works on these nodes with this securityContext                                                                                                                                                                         |
| Pod rejected: `violates PodSecurity`                                         | The namespace label did not apply, or an admission policy refuses the pod                                                                                                                                                                |
| `newuidmap: write to uid_map failed` / `failed to setup UID/GID map`         | Privilege escalation or `CAP_SETUID` is blocked — check `allowPrivilegeEscalation` and capability policies                                                                                                                               |
| `rootlesskit … creating a state directory: … permission denied` or `mkdir /run: file exists`, while a shell in the same pod can write there | The **node** loads an AppArmor profile attached to the path `/usr/bin/rootlesskit` (AppArmor 4 ships one, e.g. on Debian 13): exec-ing that path switches even an `unconfined` pod to it. Check with `sudo aa-status \| grep rootlesskit` on the node — a copy of the binary under another path runs fine. Fix it on the node: adjust or disable that profile |
| `rootlesskit … creating a state directory: … permission denied`, and the shell cannot write there either | A directory BuildKit writes to is not writable by UID 1000 — mount one `emptyDir` on each of `/home/user/.local/tmp`, `/home/user/.local/share/buildkit` and `/run/user/1000` (the hook template must add them for the workflow pod too) |
| `rootlesskit … creating a state directory: stat … no such file or directory` | An `emptyDir` on a parent (e.g. `~/.local`) hides the directories the image created — mount on each directory instead                                                                                                                    |
| `mount … permission denied` / `operation not permitted`                      | seccomp or AppArmor still confines the pod — check the node's AppArmor and that the profile fields are honoured                                                                                                                          |

**Not covered by the smoke test — ARC integration.** In `containerMode: kubernetes` the steps run in the workflow pod (UID 1000 here) while the runner (UID 1001 in `actions-runner`) creates the files of the shared work volume, such as `$GITHUB_OUTPUT`. Check on a first `workflow_dispatch` run that the build step can write them; if it cannot, give both pods a common `fsGroup` through the hook template and the runner pod spec.

## Notes

- Like the Kaniko image, the BuildKit image cannot run JavaScript actions: BuildKit fetches the source itself from a git context (`<repo>.git#<sha>:<context>`) with the job token, passed as the `GIT_AUTH_TOKEN` build secret.
- Registry credentials and secrets are written to a `0700` temporary directory removed at the end of the step.
- Layer cache: `<image>-cache:buildcache` on GHCR (`mode=max`; export failures don't fail the build).
- Single architecture (native cluster arch).
