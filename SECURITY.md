# Security policy

These reusable workflows and composite actions run **inside other
repositories**, with their tokens and secrets. A vulnerability here is a
vulnerability in every caller, so reports are welcome and treated as a priority.

## Reporting a vulnerability

Please **do not open a public issue**. Report privately through GitHub:
**Security → Report a vulnerability** on this repository
(private vulnerability reporting). Include the affected workflow or action,
the version (tag or SHA) and, if possible, a reproduction.

You can expect an acknowledgement within a few days. Fixes are released as a
new version; the advisory is published once callers have had time to update.

## Supported versions

Only the latest release receives fixes. Pin a release (`@vX.Y.Z`) or a commit
SHA, and let Renovate or Dependabot move you forward — see the pinning
strategy in the [README](README.md).

## Using these workflows safely

- **Pin** `uses: KevinDeBenedetti/github-workflows/...@vX.Y.Z` (or a SHA),
  never `@main`: a push to `main` would otherwise run in your repository
  immediately.
- **Pass secrets explicitly** (`secrets: { NAME: ${{ secrets.NAME }} }`), never
  `secrets: inherit`: each workflow receives only what it declares.
- Grant the calling job **only the permissions** the called workflow needs
  (each workflow documents them); a called workflow can never get more.
- Do not run pull-request workflows of a public repository on **persistent
  self-hosted runners** (`runner` input): fork PRs would execute on them.

## Hardening in this repository

Workflows default to `permissions: {}` and grant per-job least privilege;
third-party actions are pinned by commit SHA (Renovate, with a 3-day
`minimumReleaseAge`); downloaded tools are verified against pinned SHA-256
values (`scripts/update-tool-checksums.py`); caller inputs never reach a
`run:` script through `${{ }}`; and every push is linted by
[zizmor](https://docs.zizmor.sh) (`ci-cd.yml`, policy in `.github/zizmor.yml`).

### Repository settings (maintainer checklist)

These live outside the code and must be set in the repository settings:

- [ ] **Branch ruleset on `main`**: require a pull request with *Code Owner*
      review, and the single `CI — Gate` check (it aggregates every CI job and
      stays meaningful on release PRs, where the CI jobs are skipped); linear
      history; block force pushes and deletion. Bypass: *Repository admin*, in
      *pull request* mode only — a code owner cannot approve their own PR, so
      the maintainer's own PRs merge through it; direct pushes stay blocked.
- [ ] **Tag ruleset on `v*.*.*`**: block updates and deletion — callers and
      the internal action pins rely on release tags never moving. Leave the
      moving aliases (`v1`, `v0.N`) out of it: the release job updates them.
- [ ] **Callers of `security.yml`**: make the secret scan a *required* check
      on pull requests. On a push to a feature branch the Gitleaks config is
      read from the previous commit of that same branch, which its author
      controls; only the PR scan (config from the base branch) is a real gate.
- [ ] **Immutable releases** enabled.
- [ ] **Private vulnerability reporting** enabled.
- [ ] Actions → **Require approval for all outside collaborators** on fork PRs.
- [ ] Actions → workflow permissions: **read-only `GITHUB_TOKEN`** by default.
