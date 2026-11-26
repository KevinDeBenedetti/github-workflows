---
title: Action — config-scan
---

# Action — config-scan

Scans infrastructure-as-code files for misconfigurations (an open firewall rule, an
unencrypted volume, a container running as root) with
[Trivy](https://github.com/aquasecurity/trivy)'s `config` scanner. Terraform,
Kubernetes manifests, Helm charts and Dockerfiles are recognized per file. It is the
`config-scan` job of [`ci-terraform.yml`](../workflows/ci-terraform.md).

## Usage

```yaml
steps:
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
    with:
      persist-credentials: false

  - uses: KevinDeBenedetti/github-workflows/.github/actions/config-scan@v0.56.2 # x-release-please-version
    with:
      path: terraform
      fail-on: high
```

## Inputs

| Input         | Default | Description                                                                 |
| ------------- | ------- | --------------------------------------------------------------------------- |
| `path`        | `.`     | Directory to scan                                                           |
| `fail-on`     | `high`  | Lowest severity that fails the step: `low`, `medium`, `high` or `critical`  |
| `report-path` | `''`    | SARIF report to write; empty writes none                                    |

## Steps

1. Install the pinned `trivy` with [`install-tool`](install-tool.md)
2. `trivy config` on `path`, for the severities at `fail-on` and above
3. With `report-path`, convert the report to SARIF, findings or not
4. One error annotation per finding, on its file and line; the step fails when there is one

## Notes

- Why Trivy: one pinned binary reads Terraform, Kubernetes, Helm and Dockerfiles, it needs no Python or Node runtime on the runner, and tfsec's checks now live in it.
- A finding is silenced where it is, with a `#trivy:ignore:<ID>` comment above the resource, or for the whole scan in a `.trivyignore` file.
- Trivy refreshes its checks bundle from a registry at run time and falls back to the checks built into the binary when the registry does not answer.
- The step writes no SARIF by default. To send the findings to code scanning, set `report-path` and upload the file with `github/codeql-action/upload-sarif` from a job that grants `security-events: write`.
- The script is `config-scan.sh`; its tests are in `tests/config-scan.bats`.
