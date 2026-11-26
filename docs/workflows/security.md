---
title: Security
---

# Security

Runs **dependency audit → secret scanning → CodeQL SAST**. The audit reads every lockfile of the repository, whatever the ecosystem.
Each job is independently toggleable.

## Usage

```yaml
jobs:
  security:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/security.yml@v0.56.2 # x-release-please-version
    with:
      run-osv-scan: true
      run-node-audit: false   # deprecated, on by default until its removal
      run-codeql: true
      codeql-languages: '["javascript-typescript"]'
```

## Inputs

| Input                      | Type    | Default                         | Description                                                                 |
| -------------------------- | ------- | ------------------------------- | --------------------------------------------------------------------------- |
| `run-osv-scan`             | boolean | `false`                         | Audit the dependencies of every lockfile of the checkout with [OSV-Scanner](https://github.com/google/osv-scanner) |
| `run-node-audit`           | boolean | `true`                          | **Deprecated**, use `run-osv-scan`. Run `pnpm audit --audit-level=high`     |
| `node-working-directory`   | string  | `'.'`                           | **Deprecated** with `run-node-audit`. Path to the Node.js app               |
| `run-python-audit`         | boolean | `false`                         | **Deprecated**, use `run-osv-scan`. Run `pip-audit` on the locked dependencies (`uv export` → `uvx pip-audit`)  |
| `python-working-directory` | string  | `'.'`                           | **Deprecated** with `run-python-audit`. Path to the Python app              |
| `run-secret-scan`          | boolean | `true`                          | Run [Gitleaks](https://github.com/gitleaks/gitleaks) secret scanning        |
| `secret-scan-fetch-depth`  | number  | `0`                             | Clone depth for the secret scan (`0` = full history)                        |
| `secret-scan-ignore-inline-allow` | boolean | `false`                  | Ignore inline `gitleaks:allow` comments                                     |
| `secret-scan-upload-sarif` | boolean | `true`                          | Upload the Gitleaks SARIF report to code scanning when a leak is found — set `false` where code scanning is unavailable (private repository without GitHub Code Security) |
| `run-dependency-review`    | boolean | `false`                         | On PRs, fail when a vulnerable dependency is added (needs the dependency graph; GHAS on private repos) |
| `dependency-review-fail-on-severity` | string | `moderate`              | Lowest advisory severity that fails the review                              |
| `run-codeql`               | boolean | `true`                          | Run CodeQL SAST analysis                                                    |
| `codeql-languages`         | string  | `'["javascript-typescript"]'` | JSON array of CodeQL languages — JS and TS are one language: `javascript-typescript` |
| `runner`                   | string  | `'"ubuntu-26.04"'`              | Runner labels as JSON — e.g. `'"ubuntu-26.04"'` or `'"ubicloud-standard-2"'`  |

## Jobs

| Job            | Condition                                |
| -------------- | ---------------------------------------- |
| `osv-scan`     | `run-osv-scan: true`                     |
| `audit-node`   | `run-node-audit: true` (deprecated)      |
| `audit-python` | `run-python-audit: true` (deprecated)    |
| `secret-scan`  | `run-secret-scan: true`                  |
| `codeql`       | `run-codeql: true` (matrix per language) |

## Notes

- `osv-scan` uses the [`osv-scan`](../actions/osv-scan.md) action: one job audits every lockfile of the checkout (npm, pnpm, bun, PyPI, Go, Cargo, …) against the OSV database, without installing anything. A known vulnerability fails the job; a repository without any lockfile passes with a notice. Ignore an advisory in an `osv-scanner.toml`.
- `audit-node` and `audit-python` are deprecated: they print a warning and leave in the next breaking release, with their four inputs. Move to `run-osv-scan: true` and `run-node-audit: false`.
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
