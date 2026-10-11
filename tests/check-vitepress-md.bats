#!/usr/bin/env bats
# Tests for .github/actions/check-vitepress-md/check-vitepress-md.sh

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/check-vitepress-md/check-vitepress-md.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p docs
}

@test "passes on markdown without interpolations" {
  printf '# Title\n\nPlain text.\n' > docs/a.md
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "fails on an unescaped interpolation" {
  printf 'Use ${{ secrets.TOKEN }} here.\n' > docs/a.md
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"docs/a.md:1"* ]]
}

@test "ignores fenced code blocks" {
  printf '```yaml\ntoken: ${{ secrets.TOKEN }}\n```\n' > docs/a.md
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "ignores v-pre elements and ::: v-pre blocks" {
  printf '<code v-pre>${{ x }}</code>\n\n::: v-pre\n{{ y }}\n:::\n' > docs/a.md
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "flags interpolations again after a ::: v-pre block closes" {
  printf '::: v-pre\n{{ y }}\n:::\n{{ z }}\n' > docs/a.md
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"docs/a.md:4"* ]]
}

@test "skips non-markdown arguments (prek mode)" {
  printf '{{ x }}\n' > notes.txt
  printf 'ok\n' > docs/a.md
  run bash "$SCRIPT" docs/a.md notes.txt
  [ "$status" -eq 0 ]
}
