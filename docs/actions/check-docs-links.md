# Action — check-docs-links

Validates relative markdown links in `docs/` so that none of them escape the
`docs/` directory. Links pointing to files outside `docs/` must use absolute
GitHub URLs instead.

## Usage

```yaml
steps:
  - uses: actions/checkout@v7

  - uses: KevinDeBenedetti/github-workflows/.github/actions/check-docs-links@main
    with:
      docs-directory: docs # optional — defaults to docs
```

## Inputs

| Input            | Default | Description                                                   |
| ---------------- | ------- | ------------------------------------------------------------- |
| `docs-directory` | `docs`  | Path to the docs folder to check (depth/escape is relative to it) |

## Notes

- Scans every relative inline link / image target (`](target)`, with optional `"title"` or `<...>`) in every `docs/**/*.md` file. Absolute URLs, `/site-absolute` paths and links inside fenced code blocks are ignored.
- Resolves each target segment by segment from the file's directory (`.`, `..`, `a/../b`, `./../x`), so any path that ends up outside `docs/` is caught — not only links starting with `../`.
- Fails (exit `1`) on any escaping link, reporting it with its file and line, and suggests replacing it with an absolute GitHub URL.
- Dual-mode: in CI / standalone runs with no arguments it discovers all `docs/**/*.md`; under prek / pre-commit the staged files are passed as arguments (non-`docs/*.md` paths are ignored).
