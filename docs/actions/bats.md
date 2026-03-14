# Action — bats

Installs [Bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System) and
runs shell unit tests.

## Usage

```yaml
steps:
  - uses: actions/checkout@v4
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

## Steps

1. Install Bats `1.11.0` globally via npm
2. Run `bats <tests-dir>`

## Notes

- Pass a specific `.bats` file path to `tests-dir` to run a single test file.
- Bats helper libraries (`bats-support`, `bats-assert`, `bats-file`) are typically added as git
  submodules — check out with `submodules: true` in your checkout step.
