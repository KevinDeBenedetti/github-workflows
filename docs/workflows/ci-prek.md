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
      runner: '"ubuntu-latest"'
```

Run a single hook instead of the whole suite:

```yaml
    with:
      extra-args: renovate-config-validator --all-files
```

## Inputs

| Input               | Type    | Default             | Description                                                   |
| ------------------- | ------- | ------------------- | ------------------------------------------------------------- |
| `extra-args`        | string  | `--all-files`       | Arguments passed to `prek run` — e.g. `--all-files` or a hook id |
| `working-directory` | string  | `.`                 | Directory holding the prek config                             |
| `prek-version`      | string  | `0.4.12`            | prek release to install, without the leading `v` (or `latest`) |
| `cache`             | boolean | `true`              | Cache the prek hook environments between runs                 |
| `runner`            | string  | `'"ubuntu-latest"'` | Runner labels as JSON — `'"ubuntu-latest"'` or a label array  |

## Steps

1. Checkout
2. Verify a prek config exists (`prek.toml`, `.prek.toml`, `.pre-commit-config.yaml`
   or `.pre-commit-config.yml`) — a missing config is an **error**, not a skip
3. Run [`j178/prek-action`](https://github.com/j178/prek-action) (SHA-pinned),
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
- The action is pinned by commit SHA rather than by tag: some callers run it on
  write-capable self-hosted runners, where a mutable tag is a supply-chain risk.
  Renovate bumps it via the trailing `# v3.0.0` comment.
