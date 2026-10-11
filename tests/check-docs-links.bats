#!/usr/bin/env bats
# Tests for .github/actions/check-docs-links/check-docs-links.sh

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/check-docs-links/check-docs-links.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p docs/guide
}

@test "passes when links stay inside docs/" {
  printf '[a](../index.md)\n[b](./other.md)\n[c](sub/../x.md#anchor)\n' > docs/guide/a.md
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "fails on a ../ link climbing above docs/" {
  printf '[a](../../README.md)\n' > docs/guide/a.md
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"docs/guide/a.md:1"* ]]
}

@test "fails on escapes that do not start with ../" {
  printf '[a](./../../x.md)\n[b](sub/../../../y.md)\n' > docs/guide/a.md
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"2 link(s) escape"* ]]
}

@test "handles link titles and angle brackets" {
  printf '[a](../../x.md "Title")\n[b](<../../y.md>)\n' > docs/guide/a.md
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"2 link(s) escape"* ]]
}

@test "ignores absolute URLs and links inside fenced code blocks" {
  printf '[a](https://example.com/../../x)\n[b](/abs/path.md)\n```md\n[c](../../../z.md)\n```\n' > docs/guide/a.md
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "honours DOCS_DIR" {
  mkdir -p site
  printf '[a](../x.md)\n' > site/a.md
  DOCS_DIR=site run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "checks only the files passed as arguments (prek mode)" {
  printf '[a](../../x.md)\n' > docs/guide/bad.md
  printf '[a](../ok.md)\n' > docs/guide/good.md
  run bash "$SCRIPT" docs/guide/good.md
  [ "$status" -eq 0 ]
}
