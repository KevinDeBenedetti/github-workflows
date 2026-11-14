---
title: CI — prek hooks
---

# CI — prek hooks

Runs the calling repository's [prek](https://prek.j178.dev) (pre-commit) hooks in
CI: `prek run --all-files`.

Local hooks only protect machines that ran `prek install`. A Renovate PR, an edit
made through the GitHub web UI, a fresh clone that skipped the setup or a
`--no-verify` push all bypass them. This workflow re-runs the same config
server-side, turning the hooks into a gate instead of a convenience.

## Usage

```yaml
jobs:
  prek:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-prek.yml@main
    with:
      runner: '"ubuntu-26.04"'
```

Run a single hook instead of the whole suite:

```yaml
    with:
      extra-args: renovate-config-validator --all-files
```

On a self-hosted runner, keep the hook environments on the node instead of in
the GitHub cache (see [Hook environments on the node](#hook-environments-on-the-node)):

```yaml
    with:
      runner: '"my-scale-set"'
      prek-home: /var/cache/prek
```

## Inputs

| Input               | Type    | Default            | Description                                                                                                                                 |
| ------------------- | ------- | ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `extra-args`        | string  | `--all-files`      | Arguments passed to `prek run` — e.g. `--all-files` or a hook id                                                                            |
| `working-directory` | string  | `.`                | Directory holding the prek config                                                                                                           |
| `prek-version`      | string  | `0.4.12`           | prek release to install, without the leading `v` (or `latest`)                                                                              |
| `cache`             | boolean | `true`             | Cache the prek hook environments between runs, in the GitHub cache; ignored when `prek-home` is set                                         |
| `prek-home`         | string  | `''`               | Absolute path of a directory on the runner that keeps the hook environments between jobs, one store per config, instead of the GitHub cache |
| `timeout-minutes`   | number  | `20`               | Minutes before the job is cancelled                                                                                                         |
| `runner`            | string  | `'"ubuntu-26.04"'` | Runner labels as JSON — `'"ubuntu-26.04"'` or a label array                                                                                 |

## Steps

1. Checkout
2. Verify a prek config exists (`prek.toml`, `.prek.toml`, `.pre-commit-config.yaml`
   or `.pre-commit-config.yml`) — a missing config is an **error**, not a skip
3. With `prek-home` only, the [`prek-home`](../actions/prek-home.md) action:
   it exports `PREK_HOME` to this config's store on the node, then deletes the
   stores no run has used for 14 days
4. Run [`j178/prek-action`](https://github.com/j178/prek-action) (SHA-pinned),
   which installs prek and runs `prek run --show-diff-on-failure --color=always <extra-args>`

## Notes

- **Thin wrapper by design.** A reusable workflow checks out the *calling* repo,
  so this runs that repo's own `prek.toml` — one hook definition backing both CI
  and pre-commit, with nothing to keep in sync twice.
- **Expect overlap.** A repo that already has dedicated jobs for shellcheck,
  actionlint or Gitleaks will run those tools twice — once here through the
  hooks, once in the dedicated job. That is usually acceptable (the hooks are
  cached and fast), but `extra-args` accepts a hook id when you would rather run
  only what the other jobs do not cover.
- **Hooks need network access.** prek downloads hook repositories and, depending
  on the hook `language`, a managed toolchain (Node, Python, Go…). Self-hosted
  runners behind a strict egress policy need `github.com` plus the relevant
  package registry reachable.
- `cache: true` reuses hook environments across runs; disable it when debugging a
  hook that appears to run against a stale environment.
- **Cold runs take the longest.** The cache key is a hash of the prek config,
  with no fallback to an older entry, so the first run after a config change
  installs every hook environment from scratch, then uploads the cache, even
  when a hook failed. On a small self-hosted runner that run can outlast the
  default 20 minutes: raise `timeout-minutes` rather than turning the cache off,
  since every later run with the same config restores it. On a self-hosted
  runner, [`prek-home`](#hook-environments-on-the-node) skips the cache
  transfer altogether.
- The action is pinned by commit SHA rather than by tag: some callers run it on
  write-capable self-hosted runners, where a mutable tag is a supply-chain risk.
  Renovate bumps it via the trailing `# v3.0.0` comment.

## Hook environments on the node

Installing the hook environments is most of a cold run. The GitHub cache saves
that on GitHub's runners, but a self-hosted runner can download and upload it
more slowly than a cold install takes. `prek-home` keeps the environments in a
directory of the node instead, which outlives the runner pod:

- **One store per config.** The [`prek-home`](../actions/prek-home.md) action
  exports `PREK_HOME` to `<prek-home>/<key>/`. The key hashes the prek release,
  the runner's OS and architecture and every prek config under
  `working-directory`. A config change starts a new store, with a cold run.
- **Concurrent runs are safe.** prek locks a store itself while it clones,
  installs and collects garbage. Configs never share a store: after a run,
  `prek cache gc` keeps only what the configs it can see need, so a shared store
  would lose the environments of the other configs, even while another runner
  uses them. Runs of the same config share theirs.
- **Bounded on disk.** Each run deletes the stores no run has used for 14 days.
  An `flock` on `<key>.lock` keeps it from deleting a store that a run is
  choosing at that moment.
- **The GitHub cache is not used.** `cache` is ignored, and nothing is uploaded.

The directory must exist, be writable by the runner's user (UID `1001` in the
official `ghcr.io/actions/actions-runner` image) and sit at the same path in
every runner pod: environments hold absolute paths. The job has no `container:`,
so its steps run in the runner container itself: mount the volume there. The
runner needs `flock` and `sha256sum`, which the official image and the Ubuntu
runner images have.

With [Actions Runner Controller](https://github.com/actions/actions-runner-controller),
add the volume to the scale set's runner container. A `hostPath` gives each node
a store of its own:

```yaml
template:
  spec:
    containers:
      - name: runner
        image: ghcr.io/actions/actions-runner:latest
        command: ["/home/runner/run.sh"]
        volumeMounts:
          - name: prek-home
            mountPath: /var/cache/prek
    volumes:
      - name: prek-home
        hostPath:
          path: /var/cache/prek
          type: Directory
```

Create the directory once on each node, owned by the runner's user:

```sh
sudo install -d -o 1001 -g 1001 -m 0755 /var/cache/prek
```

Pod Security `baseline` and `restricted` forbid `hostPath` volumes. In such a
namespace, use a `local-path` PersistentVolumeClaim instead:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prek-home
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: local-path
  resources:
    requests:
      storage: 10Gi
```

```yaml
    volumes:
      - name: prek-home
        persistentVolumeClaim:
          claimName: prek-home
```

A `local-path` volume lives on one node, so every runner pod that mounts it is
scheduled there (`ReadWriteOnce` allows several pods on that node). The
provisioner creates its directory world-writable, and does not enforce the size.

Notes:

- **Pin `prek-version`.** With `latest`, the key does not change when prek
  does, and the environments of one release are reused by the next.
- **Disk use.** Each store holds every environment its config needs, toolchains
  included. Expect one store per config change in the last 14 days, per node.
- **The verbose log.** prek rewrites `prek.log` in the store on every run: when
  two runs of the same config overlap on a node, the log printed after one run
  can come from the other.
- The directory is meant to be node-local (`hostPath`, `local-path`). A network
  filesystem shared by several nodes is untested.
