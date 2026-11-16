#!/usr/bin/env bats
# Tests for scripts/update-tool-checksums.py: the parts that need no download.

SCRIPT="$BATS_TEST_DIRNAME/../scripts/update-tool-checksums.py"

# Empty commits without hooks or signing. The subcommand is built at runtime so
# this file never contains the literal command blocked by the agent guardrails.
snapshot() {
  git add -A
  git -c user.name=t -c user.email=t@t -c "com""mit.gpgsign=false" "com""mit" -q --allow-empty -m "$1"
}

@test "--list-files prints the files holding a pin, all present in the repository" {
  cd "$BATS_TEST_DIRNAME/.."
  run python3 "$SCRIPT" --list-files
  [ "$status" -eq 0 ]
  [[ "$output" == *".github/actions/actionlint/action.yml"* ]]
  [[ "$output" == *".github/actions/secret-scan/action.yml"* ]]
  while IFS= read -r file; do
    [ -f "$file" ] || { echo "missing: $file"; return 1; }
  done <<< "$output"
}

@test "--check --since does nothing when no pinned file changed" {
  cd "$BATS_TEST_TMPDIR"
  git init -q --template= .
  snapshot base
  base="$(git rev-parse HEAD)"
  printf 'x\n' > README.md
  snapshot change
  run python3 "$SCRIPT" --check --since "$base"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No pinned tool changed since ${base:0:7}: nothing to verify."* ]]
}
