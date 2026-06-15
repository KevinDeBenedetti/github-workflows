# CI — Helm

Runs **helm lint** and an optional **helm template dry-run** across one or more charts.
Catches chart errors and render failures before deployment.

## Usage

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-helm.yml@main
    with:
      chart-paths: 'charts/*'
      run-template: true
```

## Inputs

| Input             | Type    | Default       | Description                                                              |
| ----------------- | ------- | ------------- | ------------------------------------------------------------------------ |
| `run-lint`        | boolean | `true`        | Run `helm lint` on all charts                                            |
| `chart-paths`     | string  | `'charts/*'`  | Space-separated chart directory paths (supports globs)                   |
| `helm-version`    | string  | `v3.17.0`     | Helm version to install                                                  |
| `lint-strict`     | boolean | `false`       | Fail on lint warnings as well as errors (passes `--strict`)              |
| `run-template`    | boolean | `false`       | Run `helm template` dry-run on all charts to catch render errors         |
| `template-values` | string  | `''`          | Optional path to a values file used during `helm template`              |

## Steps

1. _(helm-lint, if `run-lint`)_ Checkout → Install Helm → `helm lint` each chart (`--strict` when enabled)
2. _(helm-template, if `run-template`)_ Checkout → Install Helm → `helm dependency update` + `helm template --generate-name` each chart

## Notes

- A directory counts as a chart only when it contains a `Chart.yaml`. If no matching charts are found, the job exits with an error.
- The `helm-lint` and `helm-template` jobs are independent and gated by `run-lint` / `run-template` respectively.
- `helm dependency update` failures during the template dry-run are ignored (`|| true`) so charts without resolvable dependencies still render.
