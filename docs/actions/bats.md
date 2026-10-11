# Action — bats

Installs [Bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System) and
runs shell unit tests.

## Usage

```yaml
steps:
  - uses: actions/checkout@v7
    with:
      submodules: true  # required if using bats helpers (bats-support, bats-assert, etc.)

  - uses: KevinDeBenedetti/github-workflows/.github/actions/bats@main
    with:
      tests-dir: tests/
```

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `tests-dir` | string | `tests/` | Directory (or file) containing `.bats` test files |
| `recursive` | boolean | `false` | Also run `.bats` files in sub-directories (`bats --recursive`). Off by default: vendored helpers under `test_helper/` ship their own suites |

## Steps

1. Install a pinned Bats release from the upstream repository into `$RUNNER_TEMP` (no `sudo`, no npm)
2. Run `bats [--recursive] <tests-dir>`

## Notes

- Pass a specific `.bats` file path to `tests-dir` to run a single test file.
- Bats helper libraries (`bats-support`, `bats-assert`, `bats-file`) are typically added as git
  submodules — check out with `submodules: true` in your checkout step.
