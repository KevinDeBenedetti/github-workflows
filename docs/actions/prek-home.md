---
title: Action — prek-home
---

# Action — prek-home

Keeps prek's hook environments in a directory that outlives the job, such as a
volume mounted into a self-hosted runner pod, instead of the GitHub cache.
[`ci-prek`](../workflows/ci-prek.md) runs it before
[`j178/prek-action`](https://github.com/j178/prek-action) when its `prek-home`
input is set; [Hook environments on the node](../workflows/ci-prek.md#hook-environments-on-the-node)
covers the volume to mount.

It runs two steps:

1. **Select.** Exports `PREK_HOME=<path>/<key>` for the next steps, where
   `<key>` is a hash of the prek release, `RUNNER_OS`, `RUNNER_ARCH` and every
   prek config (`prek.toml`, `.prek.toml`, `.pre-commit-config.yaml`,
   `.pre-commit-config.yml`) under `working-directory`, outside `.git` and
   `node_modules`. It touches `<path>/<key>.lock` under a shared `flock`: the
   file's modification time is the store's last use.
2. **Clean.** Deletes each store `<path>/<16 hex digits>/` whose lock file is
   older than `max-age-days`, after taking an exclusive `flock` on it without
   waiting and checking the age again. A store that a run is choosing at that
   moment is kept. Other entries of `<path>` are never touched.

## Usage

```yaml
steps:
  - uses: KevinDeBenedetti/github-workflows/.github/actions/prek-home@main
    with:
      path: /var/cache/prek
      prek-version: 0.4.12
  - uses: j178/prek-action@4e14d07f9231acabce116ccfca13b13dd9755ece # v3.0.0
    with:
      prek-version: 0.4.12
      cache: false
```

## Inputs

| Input               | Default    | Description                                                                      |
| ------------------- | ---------- | -------------------------------------------------------------------------------- |
| `path`              | (required) | Absolute path of the directory holding the stores; it must exist and be writable |
| `working-directory` | `.`        | Directory holding the prek config                                                |
| `prek-version`      | (required) | prek release the job installs, part of the store key                             |
| `max-age-days`      | `14`       | Days a store may stay unused before it is deleted (1 to 9999)                    |

## Outputs

| Output | Description                                       |
| ------ | ------------------------------------------------- |
| `path` | The store of this config, exported as `PREK_HOME` |

## Notes

- **One store per config, on purpose.** After a successful run, prek-action
  runs `prek cache gc`, which keeps only what the configs it can see need. In a
  store shared by several configs, a run would delete the environments of the
  others, possibly while another runner uses them.
- **No lock around the install.** prek locks the store itself
  (`<store>/.lock`) while it clones, installs and collects garbage, so runs of
  the same config can share their store.
- It fails with an `::error::` when `path` is not an absolute, existing,
  writable directory, or when `flock` is missing. It needs bash, `flock`
  (util-linux) and `sha256sum` (coreutils).
- The script is `prek-home.sh`; its tests are in `tests/prek-home.bats`.
