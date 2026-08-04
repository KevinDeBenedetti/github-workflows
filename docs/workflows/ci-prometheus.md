# CI — Prometheus rules

Validates `PrometheusRule` CRDs: **PromQL parsing** (`promtool check rules`) and
**alert behaviour** (`promtool test rules`).

kubeconform — see [`ci-kubernetes.yml`](ci-kubernetes.md) — validates the CRD
schema only: `expr` is an opaque string to it, so an unparseable expression
passes CI and is then dropped silently by the Prometheus rule loader in-cluster.
The alert simply never fires, with nothing to notice. This workflow closes that
gap offline.

## Usage

```yaml
jobs:
  prometheus-rules:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-prometheus.yml@main
    with:
      runner: '"ubuntu-latest"'
```

## Inputs

| Input              | Type    | Default                     | Description                                                  |
| ------------------ | ------- | --------------------------- | ------------------------------------------------------------ |
| `run-check`        | boolean | `true`                      | Run the PromQL syntax check script                           |
| `run-test`         | boolean | `true`                      | Run the alert unit-test script (skipped if the script is absent) |
| `check-script`     | string  | `scripts/promtool-check.sh` | Path to the syntax-check script in the calling repo          |
| `test-script`      | string  | `scripts/promtool-test.sh`  | Path to the unit-test script in the calling repo             |
| `promtool-version` | string  | `3.13.2`                    | Prometheus release providing promtool (no leading `v`)       |
| `yq-version`       | string  | `v4.53.3`                   | `mikefarah/yq` release tag (with leading `v`)                |
| `runner`           | string  | `'"ubuntu-latest"'`         | Runner labels as JSON — `'"ubuntu-latest"'` or a label array |

## Steps

1. Checkout
2. Install `promtool` + `yq` from pinned GitHub releases into `RUNNER_TEMP/bin`
3. _(if `run-check`)_ run `check-script`
4. _(if `run-test`)_ run `test-script`, or emit a notice when it does not exist

## Notes

- **Thin wrapper by design.** It installs the tooling and runs the *caller's*
  scripts instead of re-implementing the CRD handling. A reusable workflow
  checks out the calling repository, so one implementation backs both CI and the
  caller's local pre-commit hooks — nothing to keep in sync twice.
- promtool expects a raw rules file (`groups:` at the top level), not a
  Kubernetes CRD. Unwrapping each `PrometheusRule` to its `.spec` is the
  caller's script's job; see `scripts/promtool-check.sh` in
  [`KevinDeBenedetti/infra`](https://github.com/KevinDeBenedetti/infra) for a
  reference implementation.
- `check-script` missing is a **failure** (the workflow was asked to check
  something that is not there); `test-script` missing is a **notice**, since a
  repo may legitimately ship rules before it has a test suite.
- Both tools are installed from pinned versions rather than a package manager:
  the runner image ships neither, and pinning keeps CI reproducible. Renovate
  can bump them via the `# renovate:` comments in the calling workflow.
