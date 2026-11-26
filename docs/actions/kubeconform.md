# Action — kubeconform

Validates Kubernetes manifests with [kubeconform](https://github.com/yannh/kubeconform):
the files of a directory, and what Helm charts and kustomizations render to. Optionally
fails on a built-in API a target Kubernetes version no longer serves, and validates CRDs against the [Datree CRDs-catalog](https://github.com/datreeio/CRDs-catalog)
(cert-manager, Traefik, etc.).

## Usage

```yaml
steps:
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

  - uses: KevinDeBenedetti/github-workflows/.github/actions/kubeconform@v0.56.2 # x-release-please-version
    with:
      paths: kubernetes/
```

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `paths` | string | `kubernetes/` | Directory containing Kubernetes manifests; empty validates only what is rendered |
| `kubernetes-version` | string | `''` | Kubernetes version of the schemas (`1.33` or `1.33.2`); empty is kubeconform's default, the latest |
| `helm-charts` | string | `''` | Charts to render with `helm template`, one per line: the chart's directory, then its values files |
| `kustomizations` | string | `''` | Kustomization directories to render with `kustomize build`, one per line |
| `deprecated-api-version` | string | `''` | Kubernetes version to check for removed APIs; empty runs no check |
| `exclude` | string | `.*-values\.yaml` | Regex passed to `-ignore-filename-pattern` to exclude files |
| `include-crds-catalog` | string | `'true'` | Validate CRDs against the Datree CRDs-catalog |
| `ignore-missing-schemas` | string | `'false'` | Skip validation for resources whose schema is not found (e.g. custom CRDs not in the catalog) |

## Steps

1. Install the pinned `kubeconform` with [`install-tool`](install-tool.md), and `helm` or `kustomize` when `helm-charts` or `kustomizations` is set
2. Render each chart (`helm template`) and each kustomization (`kustomize build`) into `$RUNNER_TEMP/kubeconform-rendered`
3. Run `kubeconform -strict -summary` on the manifests under `paths` (excluding files matching `exclude`) and on the rendered files
4. With `deprecated-api-version`, run kubeconform again against that version's built-in schemas, and fail on each resource of a built-in API group it has no schema for

## Notes

- Run in strict mode — any unknown field causes a validation failure.
- `include-crds-catalog: true` (default) adds the Datree CRDs-catalog as an extra schema source,
  enabling validation of common CRD types beyond the built-in Kubernetes schemas.
- Helm values files (`*-values.yaml`) are excluded by default since they are not valid Kubernetes
  manifests.
- A chart's release name is its directory name. Paths with spaces are not supported in `helm-charts` and `kustomizations`.
- The removed-API check does not report a CRD without a schema: only the API groups Kubernetes itself serves count.
- The script is `kubeconform.sh`; its tests are in `tests/kubeconform.bats`.
