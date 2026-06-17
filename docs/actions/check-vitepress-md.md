# Action — check-vitepress-md

Detects unescaped Vue template interpolations (<code v-pre>{{ expr }}</code>) in
`docs/` markdown files. VitePress compiles every Markdown file as a Vue SFC, so
any interpolation left outside a fenced code block or a `v-pre` wrapper is
evaluated at SSR build time and crashes the build with a `TypeError` when the
referenced variable is undefined.

## Usage

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: KevinDeBenedetti/github-workflows/.github/actions/check-vitepress-md@main
    with:
      docs-directory: docs # optional — defaults to docs
```

## Inputs

| Input            | Default | Description                          |
| ---------------- | ------- | ------------------------------------ |
| `docs-directory` | `docs`  | Path to the docs folder to scan      |

## Notes

- Scans every `docs/**/*.md` file line by line for unescaped <code v-pre>{{ ... }}</code> interpolations.
- Lines inside fenced code blocks (` ``` ` or `~~~`) are treated as safe and skipped.
- Lines inside a `::: v-pre` block, or any line containing a `v-pre` attribute (e.g. `<code v-pre>`, `<span v-pre>`), are treated as safe and skipped.
- Fails (exit `1`) and prints `file:line` for each remaining unescaped interpolation, along with fix options.
- Suggested fixes:
  - Inline code: `<code v-pre>${{ expr }}</code>`
  - Inline text: `<span v-pre>{{ expr }}</span>`
  - Block: `::: v-pre` / `{{ expr }}` / `:::`
- Dual-mode: in CI / standalone runs with no arguments it discovers all `docs/**/*.md`; under prek / pre-commit the staged `.md` files are passed as arguments.
