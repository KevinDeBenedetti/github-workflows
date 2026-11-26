#!/usr/bin/env bats
# Tests for .github/actions/kubeconform/kubeconform.sh, with a fake kubeconform
# on PATH that logs its arguments, one per line, and fake helm and kustomize.

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/kubeconform/kubeconform.sh"
CATALOG='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

setup() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export LOG="$BATS_TEST_TMPDIR/args.log"
  # The removed-API pass (-output json) is logged apart and answers $FAKE_JSON.
  cat > "$BATS_TEST_TMPDIR/bin/kubeconform" << 'SH'
#!/usr/bin/env bash
case " $* " in
  *" -output json "*)
    printf '%s\n' "$@" > "$LOG.removed"
    cat "$FAKE_JSON"
    exit 0
    ;;
esac
printf '%s\n' "$@" > "$LOG"
exit "${FAKE_EXIT:-0}"
SH
  # helm and kustomize print one manifest naming their arguments.
  for tool in helm kustomize; do
    cat > "$BATS_TEST_TMPDIR/bin/$tool" << 'SH'
#!/usr/bin/env bash
[ "${FAKE_RENDER_EXIT:-0}" -eq 0 ] || exit "$FAKE_RENDER_EXIT"
echo "# ${0##*/} $*"
SH
  done
  chmod +x "$BATS_TEST_TMPDIR"/bin/*
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export RUNNER_TEMP="$BATS_TEST_TMPDIR/runner" FAKE_JSON="$BATS_TEST_TMPDIR/removed.json"
  mkdir -p "$RUNNER_TEMP"
  echo '{"resources": []}' > "$FAKE_JSON"
  export PATHS=kubernetes/ EXCLUDE='.*-values\.yaml' INCLUDE_CRDS_CATALOG=true IGNORE_MISSING_SCHEMAS=false
}

@test "defaults: strict, the built-in schemas, the CRDs catalog and the exclude pattern" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = "$(printf '%s\n' -strict -summary \
    -schema-location default \
    -schema-location "$CATALOG" \
    -ignore-filename-pattern '.*-values\.yaml' \
    kubernetes/)" ]
}

@test "without the catalog and without an exclude pattern, only the built-in schemas" {
  INCLUDE_CRDS_CATALOG=false EXCLUDE='' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = "$(printf '%s\n' -strict -summary -schema-location default kubernetes/)" ]
}

@test "ignore-missing-schemas adds the flag, and the path stays one argument" {
  IGNORE_MISSING_SCHEMAS=true PATHS='my manifests/*' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qxF -- '-ignore-missing-schemas' "$LOG"
  [ "$(tail -n 1 "$LOG")" = 'my manifests/*' ]
}

@test "a failed validation fails the step with kubeconform's exit code" {
  FAKE_EXIT=1 run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "kubernetes-version picks the schemas, X.Y completed to X.Y.0" {
  KUBERNETES_VERSION=1.33 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(sed -n '1,2p' "$LOG" | paste -sd' ' -)" = "-kubernetes-version 1.33.0" ]
  KUBERNETES_VERSION=v1.33 run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::kubeconform: kubernetes-version must look like 1.33 or 1.33.2 (got 'v1.33')"* ]]
}

@test "charts and kustomizations are rendered, then validated with the manifests" {
  HELM_CHARTS=$'charts/api charts/api/values.yaml charts/api/prod.yaml\ncharts/web' \
    KUSTOMIZATIONS=overlays/prod run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  local out="$RUNNER_TEMP/kubeconform-rendered"
  [ "$(cat "$out/helm-1-api.yaml")" = "# helm template api charts/api -f charts/api/values.yaml -f charts/api/prod.yaml" ]
  [ "$(cat "$out/helm-2-web.yaml")" = "# helm template web charts/web" ]
  [ "$(cat "$out/kustomize-1-prod.yaml")" = "# kustomize build overlays/prod" ]
  [ "$(tail -n 2 "$LOG" | paste -sd' ' -)" = "kubernetes/ $out" ]
}

@test "without manifests, only what was rendered is validated" {
  PATHS='' HELM_CHARTS=charts/api run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(tail -n 1 "$LOG")" = "$RUNNER_TEMP/kubeconform-rendered" ]
  ! grep -qx 'kubernetes/' "$LOG"
  PATHS='' run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::kubeconform: nothing to validate"* ]]
}

@test "a chart that does not render fails before any validation" {
  FAKE_RENDER_EXIT=1 HELM_CHARTS=charts/api run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::kubeconform: helm template failed for charts/api"* ]]
  [ ! -e "$LOG" ]
}

@test "a built-in API the target version removed fails; a missing CRD schema does not" {
  cat > "$FAKE_JSON" << 'JSON'
{"resources": [
  {"filename": "kubernetes/cron.yaml", "kind": "CronJob", "name": "old", "version": "batch/v1beta1", "status": "statusSkipped", "msg": ""},
  {"filename": "kubernetes/widget.yaml", "kind": "Widget", "name": "w", "version": "example.com/v1", "status": "statusSkipped", "msg": ""},
  {"filename": "kubernetes/cm.yaml", "kind": "ConfigMap", "name": "ok", "version": "v1", "status": "statusValid", "msg": ""}
]}
JSON
  DEPRECATED_API_VERSION=1.25 run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error file=kubernetes/cron.yaml,title=Removed API::CronJob old uses batch/v1beta1, which Kubernetes 1.25.0 no longer serves"* ]]
  [[ "$output" != *"Widget"* ]]
  [[ "$output" == *"1 resource(s) use an API removed in Kubernetes 1.25.0"* ]]
  [ "$(sed -n '1,2p' "$LOG.removed" | paste -sd' ' -)" = "-kubernetes-version 1.25.0" ]
  grep -qxF -- '-ignore-missing-schemas' "$LOG.removed"
}

@test "nothing removed at the target version passes, and no target runs no second pass" {
  DEPRECATED_API_VERSION=1.34.1 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No API removed in Kubernetes 1.34.1"* ]]
  rm "$LOG.removed"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$LOG.removed" ]
}
