---
title: CI — Kubernetes
---

# CI — Kubernetes

Validates Kubernetes manifests with **kubeconform**, including what **Helm charts** and
**kustomizations** render to, optionally fails on **APIs a target Kubernetes version
removed**, and optionally checks **`.env.example`** completeness. Supports the Datree
CRDs-catalog for CRD-backed resources (cert-manager, Traefik, …).

## Usage

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-kubernetes.yml@v0.56.2 # x-release-please-version
    with:
      kubeconform-paths: kubernetes/
      kubeconform-include-crds-catalog: true
```

Charts and kustomizations rendered first, against the cluster's version, with the next
minor checked for removed APIs:

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-kubernetes.yml@v0.56.2 # x-release-please-version
    with:
      kubeconform-paths: kubernetes/manifests/
      kubeconform-helm-charts: |
        charts/api charts/api/values.yaml charts/api/values-prod.yaml
        charts/web
      kubeconform-kustomizations: |
        kubernetes/overlays/prod
      kubernetes-version: '1.33'
      deprecated-api-version: '1.34'
```

## Inputs

| Input                                | Type    | Default              | Description                                                                 |
| ------------------------------------ | ------- | -------------------- | --------------------------------------------------------------------------- |
| `run-kubeconform`                    | boolean | `true`               | Validate Kubernetes manifests with kubeconform                              |
| `kubeconform-paths`                  | string  | `kubernetes/`        | Directory containing manifests to validate; empty validates only what is rendered |
| `kubeconform-helm-charts`            | string  | `''`                 | Charts to render with `helm template`, one per line: the chart's directory, then its values files |
| `kubeconform-kustomizations`         | string  | `''`                 | Kustomization directories to render with `kustomize build`, one per line    |
| `kubernetes-version`                 | string  | `''`                 | Kubernetes version of the schemas (e.g. `'1.33'`); empty is the latest      |
| `deprecated-api-version`             | string  | `''`                 | Kubernetes version to check for removed APIs (e.g. the next minor); empty runs no check |
| `kubeconform-exclude`                | string  | `'.*-values\.yaml'`  | Filename pattern to exclude from validation                                 |
| `kubeconform-include-crds-catalog`   | boolean | `true`               | Also validate against the Datree CRDs-catalog (cert-manager, Traefik, …)    |
| `kubeconform-ignore-missing-schemas` | boolean | `false`              | Skip resources with no schema in any configured location (custom CRDs)      |
| `run-env-example`                    | boolean | `false`              | Check that `.env.example` contains all required keys                        |
| `env-example-required-keys`          | string  | `''`                 | Space-separated list of keys that must be present in `.env.example`         |
| `env-example-file`                   | string  | `.env.example`       | Path to the `.env.example` file                                             |
| `runner`                             | string  | `'"ubuntu-26.04"'`   | Runner labels as JSON — `'"ubuntu-26.04"'` or a label array                 |

## Steps

1. _(kubeconform, if `run-kubeconform`)_ Checkout → run the [`kubeconform`](https://github.com/KevinDeBenedetti/github-workflows/tree/main/.github/actions/kubeconform) action over `kubeconform-paths`
2. _(env-example, if `run-env-example`)_ Checkout → verify every key in `env-example-required-keys` is present in `env-example-file`

## Notes

- The two jobs are independent: `kubeconform` is gated by `run-kubeconform`, `env-example` by `run-env-example`.
- Enable `kubeconform-ignore-missing-schemas` for custom CRDs not in the catalog (e.g. Tetragon `TracingPolicy`, Kyverno `ClusterPolicy`).
- A chart is rendered as `helm template <directory name> <chart> -f <values>…`, a kustomization with `kustomize build`. Helm and kustomize are installed only when the matching input is set, pinned and checked like kubeconform. A chart's dependencies must be vendored in its `charts/` folder: nothing is pulled.
- Keep chart and kustomization sources out of `kubeconform-paths`: templates and `kustomization.yaml` files are not manifests, and fail the raw validation.
- `deprecated-api-version` reads the same manifests against that version's built-in schemas. A resource of a built-in API group with no schema there (`batch/v1beta1` `CronJob` at 1.25, …) fails with an annotation on its file; a CRD without a schema is not reported. Quote the versions: YAML reads `1.30` as the number `1.3`.
- The `.env.example` check fails listing any missing keys (matched as `^KEY=`).
