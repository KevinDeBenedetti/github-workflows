# Action — kubeconform

Validates Kubernetes manifests with [kubeconform](https://github.com/yannh/kubeconform).
Optionally validates CRDs against the [Datree CRDs-catalog](https://github.com/datreeio/CRDs-catalog)
(cert-manager, Traefik, etc.).

## Usage

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: KevinDeBenedetti/github-workflows/.github/actions/kubeconform@main
    with:
      paths: kubernetes/
```

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `paths` | string | `kubernetes/` | Directory containing Kubernetes manifests |
| `exclude` | string | `*-values.yaml` | Filename pattern to exclude from `find` |
| `include-crds-catalog` | boolean | `true` | Validate CRDs against the Datree CRDs-catalog |

## Steps

1. Download and install `kubeconform` `0.7.0` to `/usr/local/bin`
2. Run `kubeconform -strict -summary` on all `*.yaml` files under `paths` (excluding `exclude`)

## Notes

- Run in strict mode — any unknown field causes a validation failure.
- `include-crds-catalog: true` (default) adds the Datree CRDs-catalog as an extra schema source,
  enabling validation of common CRD types beyond the built-in Kubernetes schemas.
- Helm values files (`*-values.yaml`) are excluded by default since they are not valid Kubernetes
  manifests.
