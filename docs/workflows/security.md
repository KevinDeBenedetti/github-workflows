---
title: Security
---

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
| `secret-scan-upload-sarif` | boolean | `true`                          | Upload the Gitleaks SARIF report to code scanning when a leak is found — set `false` where code scanning is unavailable (private repository without GitHub Code Security) |
| `run-dependency-review`    | boolean | `false`                         | On PRs, fail when a vulnerable dependency is added (needs the dependency graph; GHAS on private repos) |
| `dependency-review-fail-on-severity` | string | `moderate`              | Lowest advisory severity that fails the review                              |
| `run-codeql`               | boolean | `true`                          | Run CodeQL SAST analysis                                                    |
| `codeql-languages`         | string  | `'["javascript-typescript"]'` | JSON array of CodeQL languages — JS and TS are one language: `javascript-typescript` |
| `runner`                   | string  | `'"ubuntu-26.04"'`              | Runner labels as JSON — e.g. `'"ubuntu-26.04"'` or `'"my-scale-set"'` (the name of an ARC runner scale set)  |

## Jobs

| Job            | Condition                                |
| -------------- | ---------------------------------------- |
| `audit-node`   | `run-node-audit: true`                   |
| `audit-python` | `run-python-audit: true`                 |
| `secret-scan`  | `run-secret-scan: true`                  |
| `codeql`       | `run-codeql: true` (matrix per language) |

## Notes

- Secret scanning uses `actions/checkout` with `fetch-depth: 0` (full history) by default — see `secret-scan-fetch-depth`.
- Scanned range and Gitleaks configuration: the job is the [`change-base`](../actions/change-base.md) and [`secret-scan`](../actions/secret-scan.md) actions, whose pages hold the rules. In short: a pull request or a push scans the commits it brings (`base..HEAD`, from the fork point with the default branch for a new or force-pushed branch), anything else scans all fetched history; `.gitleaks.toml` and `.gitleaksignore` are read from a trusted commit, never from the commits under scan, so a change cannot allowlist its own leak.
- A finite `secret-scan-fetch-depth` can leave the change base (and the default branch) out of the clone: the scan then covers all fetched history with Gitleaks' default rules and no ignore list, and warns. Every finding `.gitleaksignore` had triaged is reported again.
- Only the PR scan is a real gate: on a push to a feature branch, the trusted commit is the branch's previous tip, which its author controls. Make the secret scan a required check on pull requests.
- Inline `gitleaks:allow` comments still silence their line (existing fixtures keep working); the job warns when a change adds one. Set `secret-scan-ignore-inline-allow: true` to disregard them.
- `audit-node` runs `pnpm audit`, `npm audit` or `bun audit` depending on the detected package manager, without installing the project or restoring its dependency cache: the audit reads the lockfile, so no dependency lifecycle script runs in this job.
- CodeQL analyses interpreted languages with `build-mode: none`; compiled ones (`go`, `c-cpp`, `swift`) use `autobuild`.
- Gitleaks SARIF results are uploaded to the Security tab on failure, unless `secret-scan-upload-sarif: false`. On a private repository without GitHub Code Security, code scanning is unavailable and the upload fails; the step is `continue-on-error`, so only its error annotations show it. Turn the upload off there: the findings stay in the job log.
- CodeQL runs in a matrix — add multiple languages to scan them in parallel.
- Requires `security-events: write` permission for Gitleaks and CodeQL (granted automatically). The secret-scan job requests it even with the upload off: job permissions cannot depend on an input.
- This workflow declares no secrets; Gitleaks is installed directly from its GitHub release and runs with no license.
- Use the [`secret-scan`](../actions/secret-scan.md) action directly for a secret scan outside this workflow.
