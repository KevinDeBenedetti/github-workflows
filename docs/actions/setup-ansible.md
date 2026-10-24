# Action — setup-ansible

Installs **ansible-lint** or **ansible** from a hash-locked requirements file:
`pip --require-hashes` checks every package, direct and transitive, against the
SHA-256 recorded in this repository. Used by `ci-ansible.yml`.

## Usage

```yaml
steps:
  - uses: actions/setup-python@v7
    with:
      python-version: '3.12'

  - uses: KevinDeBenedetti/github-workflows/.github/actions/setup-ansible@main
    with:
      tool: ansible-lint
```

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `tool` | string | — (required) | Locked tool set to install: `ansible-lint` or `ansible` |

## Steps

1. Check that `python` on `PATH` is 3.12 or newer (the locks are resolved for it)
2. `python -m pip install --require-hashes -r <tool>.txt`

## Notes

- The locks (`ansible-lint.txt`, `ansible.txt`) are compiled from one-line `.in`
  files with `uv pip compile --universal --python-version 3.12 --generate-hashes`.
  Renovate bumps the pin in the `.in` file and regenerates the lock (pip-compile
  manager), and refreshes the transitive dependencies weekly.
- No version input: a version chosen by the caller could not be hash-checked.
  The version follows the release of this repository you pin.
- Both locks pin the same versions of their shared packages (`ansible-core`,
  `cryptography`, …), so the two tools can be installed in one environment.
