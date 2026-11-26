#!/usr/bin/env bash
# Validate Kubernetes manifests with kubeconform, strictly: the files under
# PATHS, plus what the listed Helm charts and kustomizations render to, so the
# schemas are checked on what is actually applied.
#
# With DEPRECATED_API_VERSION, a second pass reads the same manifests against
# that Kubernetes version's schemas: a resource of a built-in API group with
# no schema there uses an API that version no longer serves, and fails. A
# resource of any other group (a CRD) without a schema is not reported.
#
# Env: PATHS                    directory of manifests; may be empty when something is rendered
#      EXCLUDE                  regex of file names to skip (-ignore-filename-pattern), may be empty
#      INCLUDE_CRDS_CATALOG     true also reads schemas from the Datree CRDs-catalog
#      IGNORE_MISSING_SCHEMAS   true skips resources whose schema is not found
#      KUBERNETES_VERSION       version of the schemas (1.33 or 1.33.2); empty is kubeconform's default
#      HELM_CHARTS              one chart per line: its directory, then its values files
#      KUSTOMIZATIONS           one kustomization directory per line
#      DEPRECATED_API_VERSION   target version of the removed-API pass; empty runs none
#      RUNNER_TEMP              where the rendered manifests are written
set -euo pipefail

fail() {
  echo "::error::kubeconform: $*"
  exit 1
}

# version NAME VALUE: sets VERSION to VALUE as X.Y.Z (X.Y gets .0).
version() {
  [[ "$2" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || fail "$1 must look like 1.33 or 1.33.2 (got '$2')"
  VERSION="$2"
  [ -n "${BASH_REMATCH[1]}" ] || VERSION="$2.0"
}

SCHEMA_VERSION=''
TARGET_VERSION=''
if [ -n "${KUBERNETES_VERSION:-}" ]; then
  version kubernetes-version "$KUBERNETES_VERSION"
  SCHEMA_VERSION="$VERSION"
fi
if [ -n "${DEPRECATED_API_VERSION:-}" ]; then
  version deprecated-api-version "$DEPRECATED_API_VERSION"
  TARGET_VERSION="$VERSION"
fi

TARGETS=()
if [ -n "${PATHS:-}" ]; then
  TARGETS+=("$PATHS")
fi

# Render the charts and the kustomizations, one file each.
RENDERED="${RUNNER_TEMP:-/tmp}/kubeconform-rendered"
rendered=0
n=0
while IFS= read -r line; do
  read -ra parts <<< "$line"
  [ ${#parts[@]} -gt 0 ] || continue
  chart="${parts[0]%/}"
  name="$(basename "$chart")"
  values=()
  for file in "${parts[@]:1}"; do
    values+=(-f "$file")
  done
  if [ "$rendered" -eq 0 ]; then
    rm -rf "$RENDERED"
    mkdir -p "$RENDERED"
  fi
  rendered=1
  n=$((n + 1))
  helm template "$name" "$chart" ${values[@]+"${values[@]}"} > "$RENDERED/helm-$n-$name.yaml" \
    || fail "helm template failed for $chart"
done <<< "${HELM_CHARTS:-}"
n=0
while IFS= read -r line; do
  read -ra parts <<< "$line"
  [ ${#parts[@]} -gt 0 ] || continue
  dir="${parts[0]%/}"
  if [ "$rendered" -eq 0 ]; then
    rm -rf "$RENDERED"
    mkdir -p "$RENDERED"
  fi
  rendered=1
  n=$((n + 1))
  kustomize build "$dir" > "$RENDERED/kustomize-$n-$(basename "$dir").yaml" \
    || fail "kustomize build failed for $dir"
done <<< "${KUSTOMIZATIONS:-}"
if [ "$rendered" -eq 1 ]; then
  TARGETS+=("$RENDERED")
fi
[ ${#TARGETS[@]} -gt 0 ] || fail "nothing to validate: no paths, charts or kustomizations"

ARGS=()
if [ -n "$SCHEMA_VERSION" ]; then
  ARGS+=(-kubernetes-version "$SCHEMA_VERSION")
fi
ARGS+=(-strict -summary -schema-location default)
if [ "${INCLUDE_CRDS_CATALOG:-}" = "true" ]; then
  ARGS+=(-schema-location
    "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json")
fi
FILTER=()
if [ -n "${EXCLUDE:-}" ]; then
  FILTER=(-ignore-filename-pattern "$EXCLUDE")
fi
ARGS+=(${FILTER[@]+"${FILTER[@]}"})
if [ "${IGNORE_MISSING_SCHEMAS:-}" = "true" ]; then
  ARGS+=(-ignore-missing-schemas)
fi

kubeconform "${ARGS[@]}" "${TARGETS[@]}"

[ -n "$TARGET_VERSION" ] || exit 0

# The built-in schemas only: a resource they do not know is skipped, and
# listed as such with -verbose.
REPORT="${RUNNER_TEMP:-/tmp}/kubeconform-removed-apis.json"
kubeconform -kubernetes-version "$TARGET_VERSION" -schema-location default \
  -ignore-missing-schemas -verbose -output json ${FILTER[@]+"${FILTER[@]}"} "${TARGETS[@]}" > "$REPORT"

python3 - "$REPORT" "$TARGET_VERSION" << 'PY'
import json
import sys

report, target = sys.argv[1:3]
# The API groups Kubernetes itself serves: a CRD lives in any other group.
BUILT_IN = {
    "", "admissionregistration.k8s.io", "apiextensions.k8s.io", "apiregistration.k8s.io",
    "apps", "authentication.k8s.io", "authorization.k8s.io", "autoscaling", "batch",
    "certificates.k8s.io", "coordination.k8s.io", "discovery.k8s.io", "events.k8s.io",
    "extensions", "flowcontrol.apiserver.k8s.io", "networking.k8s.io", "node.k8s.io",
    "policy", "rbac.authorization.k8s.io", "resource.k8s.io", "scheduling.k8s.io",
    "storage.k8s.io",
}
removed = 0
for resource in json.load(open(report)).get("resources") or []:
    api = resource.get("version", "")
    if resource.get("status") != "statusSkipped" or api.rpartition("/")[0] not in BUILT_IN:
        continue
    removed += 1
    print(
        f"::error file={resource.get('filename')},title=Removed API::"
        f"{resource.get('kind')} {resource.get('name')} uses {api}, which Kubernetes {target} no longer serves"
    )
if removed:
    sys.exit(f"❌ {removed} resource(s) use an API removed in Kubernetes {target}")
print(f"✅ No API removed in Kubernetes {target}")
PY
