#!/usr/bin/env bats
# Tests for scripts/check-workflow-consistency.py: the catalog and `with:` key
# checks, on a fixture repository. The script needs PyYAML: the tests are
# skipped where neither `python3 -c "import yaml"` nor `uv` can provide it.

SCRIPT="$BATS_TEST_DIRNAME/../scripts/check-workflow-consistency.py"

check() {
  if python3 -c 'import yaml' 2> /dev/null; then
    run python3 "$SCRIPT" "$@"
  elif command -v uv > /dev/null; then
    run uv run --quiet --no-project --with pyyaml python "$SCRIPT" "$@"
  else
    skip "PyYAML is not available"
  fi
}

# A consistent repository: one reusable workflow calling one action, both
# documented and listed in the catalogs.
setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p .github/workflows .github/actions/lint .github/release docs/workflows docs/actions examples
  printf '{".": "1.2.3"}\n' > .github/release/.release-please-manifest.json
  printf '{"packages": {".": {"extra-files": []}}}\n' > .github/release/release-please-config.json
  cat > .github/actions/lint/action.yml <<'YAML'
name: Lint
description: Lint
inputs:
  paths:
    description: Paths
runs:
  using: composite
  steps:
    - shell: bash
      run: "true"
YAML
  cat > .github/workflows/ci-lint.yml <<'YAML'
name: CI lint
on:
  workflow_call:
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: $/.github/actions/lint
        with:
          paths: src
YAML
  printf '# Lint\n' > docs/actions/lint.md
  printf '# CI lint\n' > docs/workflows/ci-lint.md
  printf '| Workflow | Doc |\n| --- | --- |\n| `ci-lint.yml` | [→](docs/workflows/ci-lint.md) |\n' > README.md
  {
    printf '| Workflow | Doc |\n| --- | --- |\n| `ci-lint.yml` | [→](workflows/ci-lint.md) |\n\n'
    printf '| Action | Description |\n| --- | --- |\n| [`lint`](actions/lint.md) | Lint |\n'
  } > docs/getting-started.md
}

@test "a documented, catalogued repository passes" {
  check
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 workflow(s) and 0 example(s) consistent"* ]]
}

@test "a reusable workflow missing from a catalog or without a page fails" {
  printf '| Workflow | Doc |\n| --- | --- |\n' > README.md
  rm docs/workflows/ci-lint.md
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"ci-lint.yml: no row for \`ci-lint.yml\` in the workflow table of README.md"* ]]
  [[ "$output" == *"ci-lint.yml: no documentation page docs/workflows/ci-lint.md"* ]]
  [[ "$output" != *"docs/getting-started.md"* ]]
}

@test "a workflow that is not reusable needs no catalog row" {
  printf 'name: Own CI\non:\n  push:\njobs:\n  x:\n    runs-on: ubuntu-latest\n    steps:\n      - run: "true"\n' \
    > .github/workflows/own-ci.yml
  check
  [ "$status" -eq 0 ]
}

@test "an action missing from the actions table or without a page fails" {
  mkdir .github/actions/scan
  cp .github/actions/lint/action.yml .github/actions/scan/action.yml
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *".github/actions/scan: no documentation page docs/actions/scan.md"* ]]
  [[ "$output" == *".github/actions/scan: no row linking actions/scan.md in the actions table of docs/getting-started.md"* ]]
}

@test "a with: key the action does not declare fails, in a workflow and in an action" {
  sed -i.bak 's/paths: src/path: src/' .github/workflows/ci-lint.yml
  mkdir .github/actions/wrap
  cat > .github/actions/wrap/action.yml <<'YAML'
name: Wrap
description: Wrap
runs:
  using: composite
  steps:
    - uses: $/.github/actions/lint
      with:
        paths: src
        fix: "true"
YAML
  printf '# Wrap\n' > docs/actions/wrap.md
  printf '| [`wrap`](actions/wrap.md) | Wrap |\n' >> docs/getting-started.md
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"ci-lint.yml: \`path\` is not an input of the lint action"* ]]
  [[ "$output" == *"wrap/action.yml: \`fix\` is not an input of the lint action"* ]]
}

@test "a reference to an action that does not exist fails" {
  sed -i.bak 's|actions/lint|actions/gone|' .github/workflows/ci-lint.yml
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"\`uses: \$/.github/actions/gone\` — no such action"* ]]
}
