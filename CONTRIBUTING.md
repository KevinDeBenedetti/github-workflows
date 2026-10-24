# Contributing

These workflows and actions run with the tokens and secrets of every repository
that calls them, so every change goes through a pull request, review and CI.

## Report a bug or propose a change

- Bugs and ideas: open a [GitHub issue](https://github.com/KevinDeBenedetti/github-workflows/issues).
- Security vulnerabilities: **never** in a public issue — follow [SECURITY.md](SECURITY.md).

## Set up

```sh
brew install j178/tap/prek   # or see https://prek.j178.dev
prek install                 # pre-commit and commit-msg hooks (prek.toml)
```

The hooks check whitespace, YAML/JSON, actionlint, the Renovate config, the
docs, the consistency of the reusable workflows, and the commit message.

## Make a change

1. Branch from `main`, one topic per pull request.
2. Write [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)
   (`feat:`, `fix:`, …): release-please builds the version and the changelog
   from them. The `commit-msg` hook and CI enforce it.
3. In a workflow, reference this repository's actions with
   `uses: $/.github/actions/<name>`; pin third-party actions by full commit
   SHA with a version comment. Declare a new input in both `workflow_call` and
   `workflow_dispatch` (`scripts/check-workflow-consistency.py` checks it).
4. **Tests:** a new or changed script ships with its Bats tests in `tests/`
   (`bats tests/`).
5. Update the matching page in `docs/workflows/` or `docs/actions/`.

## Review

A pull request merges once the `CI — Gate` check passes (ShellCheck, actionlint,
Bats, zizmor, prek hooks, Conventional Commits, Gitleaks, dependency review,
CodeQL) and a Code Owner has approved it.
