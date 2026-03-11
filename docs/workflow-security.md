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
      codeql-languages: '["javascript","typescript"]'
```

## Inputs

| Input                      | Type    | Default                         | Description                                                                 |
| -------------------------- | ------- | ------------------------------- | --------------------------------------------------------------------------- |
| `run-node-audit`           | boolean | `true`                          | Run `pnpm audit --audit-level=high`                                         |
| `node-working-directory`   | string  | `'.'`                           | Path to the Node.js app                                                     |
| `run-python-audit`         | boolean | `false`                         | Run `pip-audit` via `uvx`                                                   |
| `python-working-directory` | string  | `'.'`                           | Path to the Python app                                                      |
| `run-secret-scan`          | boolean | `true`                          | Run [Gitleaks](https://github.com/gitleaks/gitleaks-action) secret scanning |
| `run-codeql`               | boolean | `true`                          | Run CodeQL SAST analysis                                                    |
| `codeql-languages`         | string  | `'["javascript","typescript"]'` | JSON array of languages for CodeQL                                          |

## Jobs

| Job            | Condition                                |
| -------------- | ---------------------------------------- |
| `audit-node`   | `run-node-audit: true`                   |
| `audit-python` | `run-python-audit: true`                 |
| `secret-scan`  | `run-secret-scan: true`                  |
| `codeql`       | `run-codeql: true` (matrix per language) |

## Notes

- Secret scanning uses `actions/checkout` with `fetch-depth: 0` (full history) to scan all commits.
- Gitleaks SARIF results are uploaded to the Security tab on failure.
- CodeQL runs in a matrix — add multiple languages to scan them in parallel.
- Requires `security-events: write` permission for Gitleaks and CodeQL (granted automatically).
- `GITLEAKS_LICENSE` secret is optional; only needed for private repos with the Gitleaks enterprise plan.
