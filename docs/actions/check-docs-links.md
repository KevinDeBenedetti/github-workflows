# Action — check-docs-links

Validates relative markdown links in `docs/` so that none of them escape the
`docs/` directory. Links pointing to files outside `docs/` must use absolute
GitHub URLs instead.

## Usage

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: KevinDeBenedetti/github-workflows/.github/actions/check-docs-links@main
    with:
      docs-directory: docs # optional — defaults to docs
```

## Inputs

| Input            | Default | Description                                                   |
| ---------------- | ------- | ------------------------------------------------------------- |
| `docs-directory` | `docs`  | Path to the docs folder to check (depth/escape is relative to it) |

## Notes

- Scans relative links of the form `](../...)` in every `docs/**/*.md` file.
- Computes each file's depth within `docs/` and counts the leading `../` segments of each link.
- Fails (exit `1`) when a link climbs more `../` levels than the file's depth allows, since it would escape `docs/`.
- Reports each offending link with its file, depth, and the number of levels it goes up, and suggests replacing it with an absolute GitHub URL.
- Dual-mode: in CI / standalone runs with no arguments it discovers all `docs/**/*.md`; under prek / pre-commit the staged files are passed as arguments (non-`docs/*.md` paths are ignored).
