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

# The usage snippets of the docs are copied into other repositories, like the
# examples: same pin, same marker, same extra-files entry.
pinned_snippet() { # $1: file, $2: ref and what follows it
  printf '```yaml\njobs:\n  ci:\n    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-lint.yml@%s\n```\n' "$2" >> "$1"
}

list_extra_files() {
  local entries
  entries=$(printf '"%s",' "$@")
  printf '{"packages": {".": {"extra-files": [%s]}}}\n' "${entries%,}" > .github/release/release-please-config.json
}

@test "a docs snippet pinned to the current release, marked and listed, passes" {
  pinned_snippet docs/workflows/ci-lint.md 'v1.2.3 # x-release-please-version'
  pinned_snippet README.md 'v1.2.3 # x-release-please-version'
  list_extra_files docs/workflows/ci-lint.md README.md
  check
  [ "$status" -eq 0 ]
}

@test "a docs snippet on @main fails" {
  pinned_snippet docs/workflows/ci-lint.md 'main'
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"docs/workflows/ci-lint.md:5: internal reference pinned to @main, expected @v1.2.3"* ]]
  [[ "$output" == *"docs/workflows/ci-lint.md:5: missing '# x-release-please-version' marker"* ]]
  [[ "$output" == *"docs/workflows/ci-lint.md is not listed in extra-files"* ]]
}

@test "a README snippet behind the current release fails" {
  pinned_snippet README.md 'v1.2.2 # x-release-please-version'
  list_extra_files README.md
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"README.md:7: internal reference pinned to @v1.2.2, expected @v1.2.3"* ]]
}

@test "a docs page given as an argument is checked on its own" {
  pinned_snippet docs/actions/lint.md 'main'
  check docs/actions/lint.md
  [ "$status" -eq 1 ]
  [[ "$output" == *"docs/actions/lint.md:5: internal reference pinned to @main"* ]]
}

@test "a mention of @main outside a uses: line is not a reference" {
  printf 'A caller on `ci-lint.yml@main` follows the branch.\n' >> docs/workflows/ci-lint.md
  check
  [ "$status" -eq 0 ]
}

# ci-docker.yml is the only run of cd-docker.yml's build wiring in this
# repository's CI: its steps must stay those of cd-docker.yml.
docker_workflows() {
  cat > .github/workflows/ci-docker.yml <<'YAML'
name: CI docker
on:
  push:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Set up QEMU (multi-platform)
        if: inputs.platforms != 'linux/amd64'
        uses: docker/setup-qemu-action@aaa # v1
      - name: Build
        uses: docker/build-push-action@bbb # v1
        with:
          context: ${{ inputs.context }}
          push: false
          target: ${{ inputs.target }}
YAML
  cat > .github/workflows/cd-docker.yml <<'YAML'
name: CD docker
on:
  push:
jobs:
  docker:
    runs-on: ubuntu-latest
    steps:
      - name: Set up QEMU (multi-platform)
        if: inputs.platforms != 'linux/amd64'
        uses: docker/setup-qemu-action@aaa # v1
      - name: Login
        uses: docker/login-action@ccc # v1
      - name: Build and push
        uses: docker/build-push-action@bbb # v1
        with:
          context: ${{ inputs.context }}
          push: ${{ inputs.push }}
          target: ${{ inputs.target }}
YAML
}

@test "ci-docker.yml with the build steps of cd-docker.yml passes" {
  docker_workflows
  check
  [ "$status" -eq 0 ]
}

@test "a build input that differs between ci-docker.yml and cd-docker.yml fails" {
  docker_workflows
  sed -i.bak 's/target: ${{ inputs.target }}/target: prod/' .github/workflows/cd-docker.yml
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"cd-docker.yml: step 'Build and push' passes \`target\` differently from 'Build' in .github/workflows/ci-docker.yml"* ]]
}

@test "a build input cd-docker.yml adds without ci-docker.yml fails" {
  docker_workflows
  printf '          ulimit: nofile=1024\n' >> .github/workflows/cd-docker.yml
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"step 'Build and push' passes \`ulimit\` differently from 'Build'"* ]]
}

@test "an action version or a condition that differs between the two fails" {
  docker_workflows
  sed -i.bak -e 's/build-push-action@bbb/build-push-action@ddd/' -e "s/!= 'linux\/amd64'/!= 'linux\/arm64'/" .github/workflows/cd-docker.yml
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"step 'Build and push' has a different \`uses\` from 'Build'"* ]]
  [[ "$output" == *"step 'Set up QEMU (multi-platform)' has a different \`if\`"* ]]
}

@test "a ci-docker.yml step that cd-docker.yml does not run fails" {
  docker_workflows
  sed -i.bak 's/name: Set up QEMU (multi-platform)/name: Emulator/' .github/workflows/cd-docker.yml
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"cd-docker.yml: no step 'Set up QEMU (multi-platform)', which .github/workflows/ci-docker.yml runs"* ]]
}

@test "the steps of cd-docker.yml in another order fail" {
  docker_workflows
  cat >> .github/workflows/ci-docker.yml <<'YAML'
      - name: Login
        uses: docker/login-action@ccc # v1
YAML
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"step 'Login' does not come in the same order as 'Login'"* ]]
}
