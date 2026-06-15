# CI — Terraform

Runs **terraform validate** and **terraform fmt -check** against a Terraform root module.
Initializes with no backend and caches providers between runs.

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
| `tf-dir`            | string  | `terraform`          | Path to the Terraform root module directory                  |
| `terraform-version` | string  | `latest`             | Terraform version to install                                 |
| `runner`            | string  | `'"ubuntu-latest"'`  | Runner labels as JSON — `'"ubuntu-latest"'` or a label array |

## Steps

1. Checkout
2. Setup Terraform (`hashicorp/setup-terraform`, wrapper disabled)
3. Cache Terraform providers (`.terraform`, keyed on `.terraform.lock.hcl`)
4. `terraform init -backend=false`
5. _(if `run-validate`)_ `terraform validate`
6. _(if `run-fmt-check`)_ `terraform fmt -check -diff`

## Notes

- All steps run in `tf-dir` via `defaults.run.working-directory`.
- `init` always runs with `-backend=false` so no remote backend credentials are required for validation.
- The Terraform wrapper is disabled (`terraform_wrapper: false`) since self-hosted runners may lack a system Node.js and no step consumes the wrapper outputs.
