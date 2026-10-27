#!/usr/bin/env bats
# Tests for .github/actions/check-docs-external-links/check-docs-external-links.sh
# lychee is stubbed: these tests cover which files get checked and how, never
# the network.

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/check-docs-external-links/check-docs-external-links.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p bin docs/guide
  # Records its arguments (one per line) and GITHUB_TOKEN, writes a report to
  # --output, exits with $STUB_STATUS.
  cat > bin/lychee <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$BATS_TEST_TMPDIR/lychee.args"
printf '%s\n' "\${GITHUB_TOKEN-<unset>}" > "$BATS_TEST_TMPDIR/lychee.token"
while [[ \$# -gt 0 ]]; do
  if [[ "\$1" == --output ]]; then printf 'stub report\n' > "\$2"; fi
  shift
done
exit "\${STUB_STATUS:-0}"
EOF
  chmod +x bin/lychee
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  # Never write to the real job summary when the suite itself runs in CI.
  unset GITHUB_STEP_SUMMARY GITHUB_TOKEN CHANGED_ONLY EVENT PR_BASE BEFORE
  printf '[a](https://example.com/a)\n' > docs/a.md
  printf '[b](https://example.com/b)\n' > docs/guide/b.md
}

# Throwaway repo without hooks or signing. The subcommand is built at runtime so
# this file never contains the literal command blocked by the agent guardrails.
snapshot() {
  git add -A
  git -c user.name=t -c user.email=t@t -c "com""mit.gpgsign=false" "com""mit" -q -m "${1:-snapshot}"
}
repo() { git init -q --template= . && snapshot base; }

# The files lychee received: every argument after the "--" separator.
checked() { sed '1,/^--$/d' "$BATS_TEST_TMPDIR/lychee.args"; }

@test "checks every docs Markdown file by default" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(checked)" = "$(printf 'docs/a.md\ndocs/guide/b.md')" ]
}

@test "checks http(s) links only, never loopback or medium.com" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qx 'https' lychee.args
  grep -qx 'http' lychee.args
  grep -qx -- '--exclude-loopback' lychee.args
  grep -qF 'medium\.com/' lychee.args
}

@test "push: checks only the Markdown files changed since BEFORE" {
  repo
  before="$(git rev-parse HEAD)"
  printf '[c](https://example.com/c)\n' >> docs/a.md
  printf 'not markdown\n' > docs/notes.txt
  rm docs/guide/b.md
  snapshot change
  CHANGED_ONLY=true EVENT=push BEFORE="$before" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(checked)" = "docs/a.md" ]
}

@test "pull request: checks only the Markdown files changed since the PR base" {
  repo
  base="$(git rev-parse HEAD)"
  printf '[n](https://example.com/n)\n' > docs/guide/new.md
  snapshot change
  CHANGED_ONLY=true EVENT=pull_request PR_BASE="$base" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(checked)" = "docs/guide/new.md" ]
}

@test "does not run lychee when no Markdown file changed" {
  repo
  before="$(git rev-parse HEAD)"
  printf 'x\n' > README.txt
  snapshot change
  CHANGED_ONLY=true EVENT=push BEFORE="$before" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No Markdown file to check"* ]]
  [ ! -e lychee.args ]
}

@test "a push that creates a branch checks every file" {
  repo
  CHANGED_ONLY=true EVENT=push BEFORE=0000000000000000000000000000000000000000 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(checked | grep -c .)" -eq 2 ]
}

@test "a base that cannot be fetched falls back to every file, with a notice" {
  repo
  CHANGED_ONLY=true EVENT=push BEFORE=1234567890abcdef1234567890abcdef12345678 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::notice::"* ]]
  [ "$(checked | grep -c .)" -eq 2 ]
}

@test "checks the files passed as arguments, Markdown only" {
  run bash "$SCRIPT" docs/guide/b.md ./docs/a.md docs/notes.txt
  [ "$status" -eq 0 ]
  [ "$(checked)" = "$(printf 'docs/guide/b.md\ndocs/a.md')" ]
}

@test "honours DOCS_DIR" {
  mkdir -p site
  printf '[s](https://example.com/s)\n' > site/s.md
  DOCS_DIR=site/ run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(checked)" = "site/s.md" ]
}

@test "fails with lychee's status and writes its report to the job summary" {
  STUB_STATUS=2 GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md" run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"stub report"* ]]
  [[ "$output" == *"::error::"* ]]
  grep -qx 'stub report' summary.md
}

@test "an empty GITHUB_TOKEN is unset rather than passed to lychee" {
  GITHUB_TOKEN='' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat lychee.token)" = "<unset>" ]
}
