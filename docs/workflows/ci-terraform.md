---
title: CI — Terraform
---

# CI — Terraform

Runs **terraform validate** and **terraform fmt -check** against a Terraform root module,
and on request **tflint** and a **configuration scan**. Initializes with no backend and
caches providers between runs.

## Usage

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-terraform.yml@main
    with:
      tf-dir: terraform
      terraform-version: 1.10.0
```

## Inputs

| Input               | Type    | Default              | Description                                                  |
| ------------------- | ------- | -------------------- | ------------------------------------------------------------ |
| `run-validate`      | boolean | `true`               | Run `terraform validate` (requires init)                     |
| `run-fmt-check`     | boolean | `true`               | Run `terraform fmt -check -diff` to enforce formatting       |
| `run-tflint`        | boolean | `false`              | Lint the module with tflint (reads the module's `.tflint.hcl`). Off by default for now, on by default in a later release |
| `run-config-scan`   | boolean | `false`              | Scan the module for misconfigurations with Trivy, as annotations |
| `config-scan-fail-on` | string | `high`             | Lowest severity that fails the scan: `low`, `medium`, `high` or `critical` |
| `tf-dir`            | string  | `terraform`          | Path to the Terraform root module directory                  |
| `terraform-version` | string  | pinned (Renovate)    | Terraform version to install (`latest` still accepted)       |
| `runner`            | string  | `'"ubuntu-26.04"'`   | Runner labels as JSON — `'"ubuntu-26.04"'` or a label array  |

## Jobs

| Job           | Condition               |
| ------------- | ----------------------- |
| `terraform`   | always                  |
| `tflint`      | `run-tflint: true`      |
| `config-scan` | `run-config-scan: true` |

## Steps of the `terraform` job

1. Checkout
2. Setup Terraform (`hashicorp/setup-terraform`, wrapper disabled)
3. Cache Terraform providers (`.terraform`, keyed on the runner's OS and CPU and on `.terraform.lock.hcl`)
4. `terraform init -backend=false`
5. _(if `run-validate`)_ `terraform validate`
6. _(if `run-fmt-check`)_ `terraform fmt -check -diff`

## Notes

- `tflint` uses the [`tflint`](../actions/tflint.md) action: deprecated syntax, unused declarations and, with the plugins of the module's `.tflint.hcl`, provider-specific mistakes.
- `config-scan` uses the [`config-scan`](../actions/config-scan.md) action: each insecure resource is an error annotation on its file and line. It uploads no SARIF: a job declaring `security-events: write` would force every caller to grant it.
- Neither job runs `terraform init` or needs the backend's credentials. A `terraform plan` on the pull request is out of scope: it needs them.
- All steps of the `terraform` job run in `tf-dir` via `defaults.run.working-directory`.
- `init` always runs with `-backend=false` so no remote backend credentials are required for validation.
- The Terraform wrapper is disabled (`terraform_wrapper: false`) since a runner image may lack a system Node.js and no step consumes the wrapper outputs.
