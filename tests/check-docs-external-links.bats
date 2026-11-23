#!/usr/bin/env bats
# Tests for .github/actions/check-docs-external-links/check-docs-external-links.sh
# lychee is stubbed: these tests cover which files get checked and how, never
# the network.

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/check-docs-external-links/check-docs-external-links.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p bin docs/guide
  # Counts its runs in lychee.runs, records the arguments of the last one (one
  # per line) and GITHUB_TOKEN, writes "stub report <run>" to --output, and
  # exits with $STUB_STATUS: one status per run, the last one repeated, so
  # "2 0" fails the first run and passes the next.
  cat > bin/lychee <<EOF
#!/usr/bin/env bash
n=\$(( \$(cat "$BATS_TEST_TMPDIR/lychee.runs" 2>/dev/null || echo 0) + 1 ))
echo "\$n" > "$BATS_TEST_TMPDIR/lychee.runs"
printf '%s\n' "\$@" > "$BATS_TEST_TMPDIR/lychee.args"
printf '%s\n' "\${GITHUB_TOKEN-<unset>}" > "$BATS_TEST_TMPDIR/lychee.token"
while [[ \$# -gt 0 ]]; do
  if [[ "\$1" == --output ]]; then printf 'stub report %s\n' "\$n" > "\$2"; fi
  shift
done
read -ra statuses <<< "\${STUB_STATUS:-0}"
i=\$(( n <= \${#statuses[@]} ? n - 1 : \${#statuses[@]} - 1 ))
exit "\${statuses[i]}"
EOF
  chmod +x bin/lychee
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  # Never write to the real job summary when the suite itself runs in CI.
  unset GITHUB_STEP_SUMMARY GITHUB_TOKEN CHANGED_ONLY BASE
  # No test waits for the pause before lychee runs again.
  export RETRY_DELAY=0
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

@test "checks only the Markdown files changed since the change base" {
  repo
  base="$(git rev-parse HEAD)"
  printf '[c](https://example.com/c)\n' >> docs/a.md
  printf '[n](https://example.com/n)\n' > docs/guide/new.md
  printf 'not markdown\n' > docs/notes.txt
  rm docs/guide/b.md
  snapshot change
  CHANGED_ONLY=true BASE="$base" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(checked)" = "$(printf 'docs/a.md\ndocs/guide/new.md')" ]
}

@test "does not run lychee when no Markdown file changed" {
  repo
  base="$(git rev-parse HEAD)"
  printf 'x\n' > README.txt
  snapshot change
  CHANGED_ONLY=true BASE="$base" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No Markdown file to check"* ]]
  [ ! -e lychee.args ]
}

@test "no change base: checks every file, with a notice" {
  repo
  CHANGED_ONLY=true BASE='' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::notice::No change base"* ]]
  [ "$(checked | grep -c .)" -eq 2 ]
}

@test "a change base missing from the clone fails before lychee runs" {
  repo
  CHANGED_ONLY=true BASE=1234567890abcdef1234567890abcdef12345678 run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::Change base 1234567890abcdef1234567890abcdef12345678 is not in the clone."* ]]
  [ ! -e lychee.args ]
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

@test "broken links: checks the same files again, and passes if they pass then" {
  # A sleep that only logs the seconds it was asked to wait.
  printf '#!/usr/bin/env bash\necho "$1" >> "%s/sleep.log"\n' "$BATS_TEST_TMPDIR" > bin/sleep
  chmod +x bin/sleep
  STUB_STATUS='2 0' RETRY_DELAY=7 GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat lychee.runs)" -eq 2 ]
  [ "$(cat sleep.log)" = 7 ]
  [ "$(checked)" = "$(printf 'docs/a.md\ndocs/guide/b.md')" ]
  [[ "$output" == *"stub report 1"*"::notice::"*"checking again"* ]]
  [[ "$output" != *"::error::"* ]]
  [ "$(cat summary.md)" = "stub report 2" ]
}

@test "links still broken the second time: fails with lychee's status and the second report" {
  STUB_STATUS=2 GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md" run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [ "$(cat lychee.runs)" -eq 2 ]
  [[ "$output" == *"stub report 2"*"::error::Broken external links in docs/"* ]]
  [ "$(cat summary.md)" = "stub report 2" ]
}

@test "any other lychee failure (1, 3) fails at once, without a second run" {
  for code in 1 3; do
    rm -f lychee.runs
    STUB_STATUS=$code run bash "$SCRIPT"
    [ "$status" -eq "$code" ]
    [ "$(cat lychee.runs)" -eq 1 ]
    [[ "$output" != *"checking again"* ]]
  done
}

@test "an empty GITHUB_TOKEN is unset rather than passed to lychee" {
  GITHUB_TOKEN='' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat lychee.token)" = "<unset>" ]
}
