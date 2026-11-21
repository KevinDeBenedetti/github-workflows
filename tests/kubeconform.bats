#!/usr/bin/env bats
# Tests for .github/actions/kubeconform/kubeconform.sh, with a fake kubeconform
# on PATH that logs its arguments, one per line.

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/kubeconform/kubeconform.sh"
CATALOG='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

setup() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export LOG="$BATS_TEST_TMPDIR/args.log"
  cat > "$BATS_TEST_TMPDIR/bin/kubeconform" << 'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$LOG"
exit "${FAKE_EXIT:-0}"
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/kubeconform"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
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
