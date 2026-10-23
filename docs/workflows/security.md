# Security

Runs **dependency audits → secret scanning → CodeQL SAST** for Node.js and/or Python projects.
Each job is independently toggleable.

## Usage

```yaml
jobs:
  security:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/security.yml@main
    with:
      run-node-audit: true
      run-codeql: true
      codeql-languages: '["javascript-typescript"]'
```

## Inputs

| Input                      | Type    | Default                         | Description                                                                 |
| -------------------------- | ------- | ------------------------------- | --------------------------------------------------------------------------- |
| `run-node-audit`           | boolean | `true`                          | Run `pnpm audit --audit-level=high`                                         |
| `node-working-directory`   | string  | `'.'`                           | Path to the Node.js app                                                     |
| `run-python-audit`         | boolean | `false`                         | Run `pip-audit` on the locked dependencies (`uv export` → `uvx pip-audit`)  |
| `python-working-directory` | string  | `'.'`                           | Path to the Python app                                                      |
| `run-secret-scan`          | boolean | `true`                          | Run [Gitleaks](https://github.com/gitleaks/gitleaks) secret scanning        |
| `secret-scan-fetch-depth`  | number  | `0`                             | Clone depth for the secret scan (`0` = full history)                        |
| `secret-scan-ignore-inline-allow` | boolean | `false`                  | Ignore inline `gitleaks:allow` comments                                     |
| `run-dependency-review`    | boolean | `false`                         | On PRs, fail when a vulnerable dependency is added (needs the dependency graph; GHAS on private repos) |
| `dependency-review-fail-on-severity` | string | `moderate`              | Lowest advisory severity that fails the review                              |
| `run-codeql`               | boolean | `true`                          | Run CodeQL SAST analysis                                                    |
| `codeql-languages`         | string  | `'["javascript-typescript"]'` | JSON array of CodeQL languages — JS and TS are one language: `javascript-typescript` |
| `runner`                   | string  | `'"ubuntu-latest"'`             | Runner labels as JSON — e.g. `'"ubuntu-latest"'` or `'["self-hosted","linux","k3s","kaniko"]'` |

## Jobs

| Job            | Condition                                |
| -------------- | ---------------------------------------- |
| `audit-node`   | `run-node-audit: true`                   |
| `audit-python` | `run-python-audit: true`                 |
| `secret-scan`  | `run-secret-scan: true`                  |
| `codeql`       | `run-codeql: true` (matrix per language) |

## Notes

- Secret scanning uses `actions/checkout` with `fetch-depth: 0` (full history) by default — see `secret-scan-fetch-depth`.
- Scanned range: on a pull request, every commit the PR brings (`base..head`); on a push, `before..HEAD` including commits brought in by a merge commit; otherwise (first push of a branch, manual run, range outside a shallow clone) all fetched history.
- **Gitleaks config is read from the trusted side of the range**, never from the commits under scan: `.gitleaks.toml` and `.gitleaksignore` come from the PR base (or the commit before the push). A change can therefore not allowlist its own leak — config changes apply once merged, and the job warns when the scanned range modifies them. Without a trusted commit (first push, manual run) gitleaks' default rules apply and the repository's allowlist is ignored — expect false positives there that a PR scan would not report.
- Only the PR scan is a real gate: on a push to a feature branch, the trusted commit is the branch's previous tip, which its author controls. Make the secret scan a required check on pull requests.
- Inline `gitleaks:allow` comments still silence their line (existing fixtures keep working); the job warns when a change adds one. Set `secret-scan-ignore-inline-allow: true` to disregard them.
- A trusted `.gitleaks.toml` that `[extend]`s a `path` inside the repository: that file is restored from the trusted commit too (and its changes are flagged like the config's). Paths outside the repository (absolute, or with `..`) fail the job.
- `audit-node` runs `pnpm audit`, `npm audit` or `bun audit` depending on the detected package manager.
- CodeQL analyses interpreted languages with `build-mode: none`; compiled ones (`go`, `c-cpp`, `swift`) use `autobuild`.
- Gitleaks SARIF results are uploaded to the Security tab on failure.
- CodeQL runs in a matrix — add multiple languages to scan them in parallel.
- Requires `security-events: write` permission for Gitleaks and CodeQL (granted automatically).
- This workflow declares no secrets; Gitleaks is installed directly from its GitHub release and runs with no license.
