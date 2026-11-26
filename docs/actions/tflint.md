---
title: Action — tflint
---

# Action — tflint

Lints a Terraform module with [tflint](https://github.com/terraform-linters/tflint):
deprecated syntax, unused declarations and, with the plugins the module's `.tflint.hcl`
declares, provider-specific mistakes. It is the `tflint` job of
[`ci-terraform.yml`](../workflows/ci-terraform.md).

## Usage

```yaml
steps:
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
    with:
      persist-credentials: false

  - uses: KevinDeBenedetti/github-workflows/.github/actions/tflint@v0.56.2 # x-release-please-version
    with:
      tf-dir: terraform
```

## Inputs

| Input    | Default        | Description                                                                             |
| -------- | -------------- | --------------------------------------------------------------------------------------- |
| `tf-dir` | `terraform`    | Directory of the Terraform module (its `.tflint.hcl` is read from there)                |
| `token`  | the job token  | Token for tflint's plugin downloads from GitHub releases (lifts the API rate limit)     |

## Steps

1. Install the pinned `tflint` with [`install-tool`](install-tool.md)
2. `tflint --chdir=<tf-dir> --init`: install the plugins `.tflint.hcl` declares
3. `tflint --chdir=<tf-dir> --format=compact`: one line per issue

## Notes

- Without a `.tflint.hcl`, tflint runs its bundled Terraform ruleset.
- The step fails with tflint's exit code when it finds an issue. Set the lowest failing severity, or disable a rule, in `.tflint.hcl`.
- No `terraform init` is needed: tflint reads the module's files, and calls local modules only.
- The script is `tflint.sh`; its tests are in `tests/tflint.bats`.
