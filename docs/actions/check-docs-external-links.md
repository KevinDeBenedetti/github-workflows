# Action — check-docs-external-links

Checks the `http(s)` links of the Markdown files in `docs/` with
[lychee](https://lychee.cli.rs). By default only the files changed by the push
or pull request are checked, so a page that rotted elsewhere in the docs never
fails an unrelated change.

## Usage

```yaml
steps:
  - uses: actions/checkout@v7
    with:
      persist-credentials: false

  - uses: KevinDeBenedetti/github-workflows/.github/actions/check-docs-external-links@main
    with:
      docs-directory: docs # optional — defaults to docs
```

## Inputs

| Input            | Default                                | Description                                                                             |
| ---------------- | -------------------------------------- | --------------------------------------------------------------------------------------- |
| `docs-directory` | `docs`                                 | Path to the docs folder to check                                                        |
| `changed-only`   | `true`                                 | Check only the Markdown files changed by the push or pull request (`false`: every file) |
| `github-token`   | <code v-pre>${{ github.token }}</code> | Token lychee uses for github.com links, which are rate-limited without one              |

## Notes

- **Changed files**: diffed against the pull request's base commit, or against the commit before the push. A shallow checkout is enough: the action fetches that one commit. A push that creates a branch, a manual run, or a base that cannot be fetched checks every file instead.
- **Never checked**: links inside code blocks, relative links (the [`check-docs-links`](check-docs-links.md) action's job), loopback addresses such as `localhost` dev servers, and `medium.com`, which answers any non-browser client with a 403. Add a `.lycheeignore` at the repository root (one regex per line) for anything else.
- **github.com**: requests go through `github-token`, so they are not rate-limited. A link to a private repository fails, as it does for readers.
- Retries a failing link 3 times, 5 s apart, with a 30 s timeout. Fails with lychee's exit code (`2`) on any broken link; the lychee report, with the file and line of each broken link, is printed and written to the job summary.
- lychee is downloaded from its GitHub release and checked against a SHA-256 pinned in the action. After a version bump, refresh it with `scripts/update-tool-checksums.py`.
- Locally, with `lychee` on the `PATH`: `bash .github/actions/check-docs-external-links/check-docs-external-links.sh docs/page.md`.
