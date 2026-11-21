#!/usr/bin/env bash
# Validate the Kubernetes manifests under PATHS with kubeconform, strictly.
#
# Env: PATHS                    directory of manifests
#      EXCLUDE                  regex of file names to skip (-ignore-filename-pattern), may be empty
#      INCLUDE_CRDS_CATALOG     true also reads schemas from the Datree CRDs-catalog
#      IGNORE_MISSING_SCHEMAS   true skips resources whose schema is not found
set -euo pipefail

ARGS=(-strict -summary -schema-location default)
if [ "${INCLUDE_CRDS_CATALOG:-}" = "true" ]; then
  ARGS+=(-schema-location
    "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json")
fi
if [ -n "${EXCLUDE:-}" ]; then
  ARGS+=(-ignore-filename-pattern "$EXCLUDE")
fi
if [ "${IGNORE_MISSING_SCHEMAS:-}" = "true" ]; then
  ARGS+=(-ignore-missing-schemas)
fi

kubeconform "${ARGS[@]}" "$PATHS"
