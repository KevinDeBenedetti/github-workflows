# CI — Kubernetes

Validates Kubernetes manifests with **kubeconform** and optionally checks **`.env.example`** completeness.
Supports the Datree CRDs-catalog for CRD-backed resources (cert-manager, Traefik, …).

## Usage

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-kubernetes.yml@main
    with:
      kubeconform-paths: kubernetes/
      kubeconform-include-crds-catalog: true
```

## Inputs

| Input                                | Type    | Default              | Description                                                                 |
| ------------------------------------ | ------- | -------------------- | --------------------------------------------------------------------------- |
| `run-kubeconform`                    | boolean | `true`               | Validate Kubernetes manifests with kubeconform                              |
| `kubeconform-paths`                  | string  | `kubernetes/`        | Directory containing manifests to validate                                  |
| `kubeconform-exclude`                | string  | `'.*-values\.yaml'`  | Filename pattern to exclude from validation                                 |
| `kubeconform-include-crds-catalog`   | boolean | `true`               | Also validate against the Datree CRDs-catalog (cert-manager, Traefik, …)    |
| `kubeconform-ignore-missing-schemas` | boolean | `false`              | Skip resources with no schema in any configured location (custom CRDs)      |
| `run-env-example`                    | boolean | `false`              | Check that `.env.example` contains all required keys                        |
| `env-example-required-keys`          | string  | `''`                 | Space-separated list of keys that must be present in `.env.example`         |
| `env-example-file`                   | string  | `.env.example`       | Path to the `.env.example` file                                             |
| `runner`                             | string  | `'"ubuntu-latest"'`  | Runner labels as JSON — `'"ubuntu-latest"'` or a label array                |

## Steps

1. _(kubeconform, if `run-kubeconform`)_ Checkout → run the [`kubeconform`](https://github.com/KevinDeBenedetti/github-workflows/tree/main/.github/actions/kubeconform) action over `kubeconform-paths`
2. _(env-example, if `run-env-example`)_ Checkout → verify every key in `env-example-required-keys` is present in `env-example-file`

## Notes

- The two jobs are independent: `kubeconform` is gated by `run-kubeconform`, `env-example` by `run-env-example`.
- Enable `kubeconform-ignore-missing-schemas` for custom CRDs not in the catalog (e.g. Tetragon `TracingPolicy`, Kyverno `ClusterPolicy`).
- The `.env.example` check fails listing any missing keys (matched as `^KEY=`).
