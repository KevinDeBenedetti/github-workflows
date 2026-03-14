# Action — setup-python

Installs Python with **uv** and restores the uv dependency cache.

## Usage

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: KevinDeBenedetti/github-workflows/.github/actions/setup-python@main
    with:
      python-version: '3.12'
```

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `python-version` | string | `'3.12'` | Python version to install |
| `working-directory` | string | `'.'` | Directory containing `pyproject.toml` |
| `install` | boolean | `true` | Run `uv sync` after setup |

## Outputs

| Output | Description |
|---|---|
| `cache-hit` | Whether the uv cache was restored |

## Steps

1. Install [uv](https://github.com/astral-sh/uv) (latest)
2. Setup Python `python-version`
3. Restore uv cache keyed on `uv.lock`
4. Run `uv sync --frozen`

## Notes

- `install: 'false'` skips the `uv sync` step — useful when you only need the Python + uv toolchain.
- Cache key is scoped to `runner.os`, `python-version`, and the hash of `uv.lock`, so cache is invalidated when dependencies change.
