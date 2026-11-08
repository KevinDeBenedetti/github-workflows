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
- Scanned range: on a pull request, every commit the PR brings (`base..head`); on a push, `before..HEAD` including commits brought in by a merge commit. When `before` is not in the clone — a force push rewrote it away, or the branch is new — a push to any branch but the default one scans what the branch holds beyond the default branch (`merge-base..HEAD`), leaving the commits already there to the default branch's own scans. Otherwise (manual or scheduled run, a force push or first push of the default branch itself, a finite `secret-scan-fetch-depth` that leaves both `before` and the default branch out of the clone) all fetched history.
- **Gitleaks config is read from the trusted side of the range**, never from the commits under scan: `.gitleaks.toml` and `.gitleaksignore` come from the PR base (or the commit before the push, or the merge-base with the default branch when that commit is gone). A change can therefore not allowlist its own leak — config changes apply once merged, and the job warns when the scanned range modifies them. A manual run reads them from the default branch, which went through review, and a scheduled run from the default branch's tip it checks out. Without a trusted commit (a force push or first push of the default branch, a push whose `before` falls outside a shallow clone, or a manual run whose clone lacks the default branch because of a finite `secret-scan-fetch-depth`) gitleaks' default rules apply and the repository's allowlist is ignored: the job warns, and every finding `.gitleaksignore` had triaged in the history is reported again.
- Only the PR scan is a real gate: on a push to a feature branch, the trusted commit is the branch's previous tip, which its author controls. Make the secret scan a required check on pull requests.
- Inline `gitleaks:allow` comments still silence their line (existing fixtures keep working); the job warns when a change adds one. Set `secret-scan-ignore-inline-allow: true` to disregard them.
- A trusted `.gitleaks.toml` that `[extend]`s a `path` inside the repository: that file is restored from the trusted commit too (and its changes are flagged like the config's). Paths outside the repository (absolute, or with `..`) fail the job.
- `audit-node` runs `pnpm audit`, `npm audit` or `bun audit` depending on the detected package manager, without installing the project or restoring its dependency cache: the audit reads the lockfile, so no dependency lifecycle script runs in this job.
- CodeQL analyses interpreted languages with `build-mode: none`; compiled ones (`go`, `c-cpp`, `swift`) use `autobuild`.
- Gitleaks SARIF results are uploaded to the Security tab on failure, unless `secret-scan-upload-sarif: false`. On a private repository without GitHub Code Security, code scanning is unavailable and the upload fails; the step is `continue-on-error`, so only its error annotations show it. Turn the upload off there: the findings stay in the job log.
- CodeQL runs in a matrix — add multiple languages to scan them in parallel.
- Requires `security-events: write` permission for Gitleaks and CodeQL (granted automatically). The secret-scan job requests it even with the upload off: job permissions cannot depend on an input.
- This workflow declares no secrets; Gitleaks is installed directly from its GitHub release and runs with no license.
