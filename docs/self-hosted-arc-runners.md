---
title: Running on self-hosted ARC runners
---

# Running on self-hosted ARC runners

The perf and SEO workflows ([`perf-sitespeed`](./workflows/perf-sitespeed.md),
[`perf-lighthouse`](./workflows/perf-lighthouse.md),
[`perf-unlighthouse`](./workflows/perf-unlighthouse.md) and
[`seo-crawl`](./workflows/seo-crawl.md)) run on an
[Actions Runner Controller](https://github.com/actions/actions-runner-controller)
scale set in Kubernetes container mode, with no Docker daemon, no Chrome and no
sudo on the runner. The jobs that need Chrome run inside a pinned image as their
job container: in Kubernetes mode, a workflow pod of its own. They keep working
unchanged on GitHub-hosted runners, where Docker runs the same container.

## Where each job runs

| Workflow          | Job            | Runs in                                                         |
| ----------------- | -------------- | --------------------------------------------------------------- |
| perf-sitespeed    | `sitespeed`    | `sitespeed-image`, as a workflow pod                            |
| perf-sitespeed    | `history`      | the runner pod (git)                                            |
| perf-lighthouse   | `lighthouse`   | `browser-image`, as a workflow pod                              |
| perf-lighthouse   | `statuses`     | the runner pod (curl, jq, the `statuses: write` token)          |
| perf-unlighthouse | `unlighthouse` | `browser-image`, as a workflow pod                              |
| seo-crawl         | `crawl`        | the runner pod (Node from `actions/setup-node`, jq; no browser) |

`browser-image` defaults to the same sitespeed.io image as `sitespeed-image`: one
image, pulled once per node, holds Node and Google Chrome for every perf job.

## Runner requirements

1. **Kubernetes container mode**: `containerMode.type: kubernetes` in the scale set,
   so the runner container hooks run each `container:` job as a workflow pod.
2. **Container-less jobs allowed**: the `history`, `statuses` and `crawl` jobs run on
   the runner pod itself. The chart sets `ACTIONS_RUNNER_REQUIRE_JOB_CONTAINER=true`
   in Kubernetes mode; set it to `"false"` on the runner container. The runner image
   needs bash, git, curl and jq: the official `ghcr.io/actions/actions-runner` image
   has them.
3. **The workflow pod runs as the runner's UID**, `1001`: the job writes into the
   runner's work volume, whose files belong to it. Under Docker, the workflows pass
   `--user 1001`; Kubernetes ignores container options, so the hook template sets
   it. No root is needed anywhere.
4. **`/dev/shm` in memory**: Chrome keeps its shared memory there. A pod gets 64 MiB,
   which a heavy page fills; mount an in-memory `emptyDir` of 1 GiB on `/dev/shm`
   through the hook template. Without it, the workflows see a small `/dev/shm` and
   start Chrome with `--disable-dev-shm-usage` (its shared memory moves to `/tmp`,
   a little slower). Under Docker, `--shm-size=1g` gives the same 1 GiB.
5. **Pod Security `baseline`** is enough: no privileged container, no added
   capability, no host path. Chrome runs with `--no-sandbox`: its sandbox needs user
   namespaces or a setuid helper, which an unprivileged container without
   `CAP_SYS_ADMIN` or privilege escalation cannot offer. The container is the
   boundary, which is why the jobs that hold a write token (`history`, `statuses`)
   never run in it.
6. **Egress on 443** (and DNS): `github.com` and its release downloads (jq),
   `api.github.com`, `*.actions.githubusercontent.com` and the artifact
   storage (`*.blob.core.windows.net`) when `upload-artifact` is on,
   `registry.npmjs.org` (Lighthouse CI, Unlighthouse, linkinator) and the
   audited site. The node pulls the image (about 1.3 GB) from Docker Hub.
7. **amd64 nodes** for Google Chrome: it has no Linux arm64 build (the arm64 variant
   of the sitespeed.io image ships Chromium).
8. **Room on the node**: the workflow pod lands where the runner's work volume is.
   Give it memory for Chrome and Node plus the `/dev/shm` volume, which counts
   against the pod's memory: 4 GiB covers a sitespeed.io run.

## Hook template

The runner reads it from `ACTIONS_RUNNER_CONTAINER_HOOK_TEMPLATE`, a file mounted
from a ConfigMap. Fields of the `$job` container are merged into the workflow pod's
job container; `volumes` are added to the pod.

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1001
    runAsGroup: 1001
  containers:
    - name: "$job"
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: [ALL]
      volumeMounts:
        - name: dshm
          mountPath: /dev/shm
      resources:
        requests:
          cpu: 1000m
          memory: 2Gi
        limits:
          memory: 4Gi
  volumes:
    - name: dshm
      emptyDir:
        medium: Memory
        sizeLimit: 1Gi
```

On the runner container of the scale set:

```yaml
env:
  - name: ACTIONS_RUNNER_CONTAINER_HOOK_TEMPLATE
    value: /home/runner/hook-templates/hook-template.yaml
  - name: ACTIONS_RUNNER_REQUIRE_JOB_CONTAINER
    value: "false"
```

## Calling a workflow on the scale set

```yaml
jobs:
  sitespeed:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/perf-sitespeed.yml@main
    permissions:
      contents: write
    with:
      runner: '"my-scale-set"'
      device: both
```

`runner` takes the scale set's name as JSON. Measure from a network other than the
site's own: from inside the cluster that serves the site, LCP, TTFB and the
Lighthouse scores are skewed.
