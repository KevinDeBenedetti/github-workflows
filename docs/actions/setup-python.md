# Action — setup-python

Installs Python with **uv** and restores the uv dependency cache.

## Usage

```yaml
steps:
  - uses: actions/checkout@v7

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

1. Install [uv](https://github.com/astral-sh/uv) (latest), with uv's own dependency cache enabled
2. Setup Python `python-version`
3. Run `uv sync --frozen`

## Notes

- `install: 'false'` skips the `uv sync` step — useful when you only need the Python + uv toolchain.
- Caching is handled by `setup-uv` itself, not by a separate `actions/cache` step. `setup-uv` exports `UV_CACHE_DIR`, so caching the conventional `~/.cache/uv` path by hand does nothing on GitHub-hosted runners — uv writes to `$RUNNER_TEMP/setup-uv-cache` there.
- Cache is enabled explicitly rather than left on `setup-uv`'s `auto` default: `auto` only turns caching on for GitHub-hosted runners, and these workflows can be routed onto self-hosted runners through their `runner` input.
- The cache key covers `runner.os`, `python-version` (via `cache-suffix`), and the hash of the dependency files `setup-uv` tracks by default — `uv.lock`, `pyproject.toml`, and `requirements`/`constraints` files — so it is invalidated when dependencies change.
