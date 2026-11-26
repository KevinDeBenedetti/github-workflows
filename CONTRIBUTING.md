# Contributing

These workflows and actions run with the tokens and secrets of every repository
that calls them, so every change goes through a pull request, review and CI.

## Report a bug or propose a change

- Bugs and ideas: open a [GitHub issue](https://github.com/KevinDeBenedetti/github-workflows/issues).
- Security vulnerabilities: **never** in a public issue — follow [SECURITY.md](SECURITY.md).

## Set up

```sh
brew install j178/tap/prek bats-core   # or see https://prek.j178.dev
prek install                           # pre-commit, commit-msg and pre-push hooks (prek.toml)
```

On each commit the hooks check whitespace, YAML/JSON, actionlint, ShellCheck,
the Renovate config, the docs, the consistency of the reusable workflows, and
the commit message. Before a push that touches a script, an action or a test,
they run the Bats suite (over a minute).

The gate also runs [zizmor](https://docs.zizmor.sh), which has no hook. Run it
by hand after changing a workflow or an action, at the version the `ci-zizmor`
job of `ci-cd.yml` pins:

```sh
uvx zizmor==<version> --persona pedantic --config .github/zizmor.yml .
```

## What belongs here

A workflow or an action enters this repository once two repositories need it;
until then it stays in the caller. A reusable workflow nothing outside this
repository calls any more is removed, with the actions, tests, docs page,
example and README row only it uses, as a breaking change. The one exception
is `propagate-release.yml`, which this repository's own `ci-cd.yml` and
`propagate.yml` share.

To list the callers of a workflow across an account, private repositories
included:

```sh
gh search code "KevinDeBenedetti/github-workflows/.github/workflows/<name>.yml" --owner <account>
```

## Make a change

1. Branch from `main`, one topic per pull request.
2. Write [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)
   (`feat:`, `fix:`, …): release-please builds the version and the changelog
   from them. The `commit-msg` hook and CI enforce it.
3. In a workflow, reference this repository's actions with
   `uses: $/.github/actions/<name>`; pin third-party actions by full commit
   SHA with a version comment. A reusable workflow has `workflow_call` as its
   only trigger: `ci-cd.yml` runs it on every push and pull request.
4. **Tests:** a new or changed script ships with its Bats tests in `tests/`
   (`bats tests/`). A script that calls the GitHub API is tested against the
   fake curl of `tests/helpers/fake-github.bash`.
5. Update the matching page in `docs/workflows/` or `docs/actions/`. A new
   workflow or action also needs its page and its row in the tables of
   `README.md` and `docs/getting-started.md`: the same script checks them, and
   the `with:` keys passed to this repository's actions.
6. **Downloaded tools** (actionlint, Gitleaks, lychee, …) are pinned in
   `.github/actions/install-tool/tools.json`, the only place a pin lives: the
   `install-tool` action reads it at run time. After changing a version
   there, run `scripts/update-tool-checksums.py` to refresh the checksums.
   On a Renovate pull request, `tool-checksums.yml` does it and commits the
   result.

## Review

A pull request merges once the `CI — Gate` check passes (ShellCheck, actionlint,
Bats, zizmor, prek hooks, a test image build, Conventional Commits, Gitleaks,
dependency review, CodeQL) and a Code Owner has approved it.

## Releases

release-please keeps a release pull request open on `main`; merging it tags the
release, and `ci-cd.yml` then opens a pull request in every consumer
repository, each of which runs that repository's whole CI.

- **Cadence:** merge the release pull request once a week, so consumers get
  one propagation pull request a week. Merge it earlier only for a fix a
  caller waits for.
- **Before 1.0:** a breaking change ships as a minor, so `ci-cd.yml` passes
  `pre-major-alias: minor` and only `v0.<minor>` moves.
- **1.0.0:** the interface is declared stable once the last 0.x removals have
  shipped: the duplicated `workflow_dispatch` triggers, the deprecated token
  parameters of `release.yml`, and the deprecated docs and audit inputs of
  `ci-shell.yml`, `ci-node.yml` and `security.yml`. The release after them is
  `1.0.0`, cut with a `Release-As: 1.0.0` footer on a commit to `main`. From
  then on a breaking change is a major, `release.yml` moves `v<major>` and
  ignores `pre-major-alias`.
