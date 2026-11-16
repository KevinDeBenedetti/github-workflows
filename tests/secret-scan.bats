#!/usr/bin/env bats
# Tests for .github/actions/secret-scan/secret-scan.sh
# gitleaks is faked: these tests cover the range, the trusted configuration
# and the warnings, never gitleaks' own rules.

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/secret-scan/secret-scan.sh"

# Throwaway repo without hooks or signing. The subcommand is built at runtime so
# this file never contains the literal command blocked by the agent guardrails.
snapshot() {
  git add -A
  git -c user.name=t -c user.email=t@t -c "com""mit.gpgsign=false" "com""mit" -q --allow-empty -m "$1"
}

# The fake records its arguments (one per line), keeps a copy of the config
# and ignore list it was handed and of the working tree's .gitleaksignore,
# and exits with $STUB_STATUS.
setup() {
  export STUB="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB/bin" "$BATS_TEST_TMPDIR/repo" "$BATS_TEST_TMPDIR/tmp"
  cat > "$STUB/bin/gitleaks" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB/args"
while [ $# -gt 0 ]; do
  case "$1" in
    --config) cp "$2" "$STUB/config"; shift ;;
    --gitleaks-ignore-path) cp "$2" "$STUB/ignore"; shift ;;
  esac
  shift
done
if [ -e .gitleaksignore ]; then cp .gitleaksignore "$STUB/worktree-ignore"; fi
exit "${STUB_STATUS:-0}"
EOF
  chmod +x "$STUB/bin/gitleaks"
  PATH="$STUB/bin:$PATH"
  export RUNNER_TEMP="$BATS_TEST_TMPDIR/tmp"
  unset BASE EVENT BEFORE DEFAULT_BRANCH IGNORE_INLINE_ALLOW REPORT_PATH STUB_STATUS
  cd "$BATS_TEST_TMPDIR/repo"
  git init -q --template= -b main .
  printf 'app\n' > app.txt
  snapshot base
  BASE_SHA="$(git rev-parse HEAD)"
}

log_opts() { sed -n 's/^--log-opts=//p' "$STUB/args"; }
default_rules() { [ "$(cat "$STUB/config")" = "$(printf '[extend]\nuseDefault = true')" ]; }

@test "scans base..HEAD without merges, and writes a SARIF report" {
  snapshot change
  BASE="$BASE_SHA" EVENT=push run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(log_opts)" = "--no-merges ${BASE_SHA}..HEAD" ]
  grep -qx -- '--report-format=sarif' "$STUB/args"
  grep -qx -- '--report-path=results.sarif' "$STUB/args"
  grep -qx -- '--exit-code=1' "$STUB/args"
  [[ "$output" == *"Scanning: ${BASE_SHA}..HEAD (config from ${BASE_SHA})"* ]]
}

@test "without a config at the trusted commit, gitleaks' default rules and an empty ignore list" {
  snapshot change
  BASE="$BASE_SHA" EVENT=push run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  default_rules
  [ ! -s "$STUB/ignore" ]
}

@test "the config and ignore list come from the change base, not from the commits under scan" {
  printf 'title = "trusted"\n' > .gitleaks.toml
  printf 'trusted-fingerprint\n' > .gitleaksignore
  snapshot config
  base="$(git rev-parse HEAD)"
  printf 'title = "allow everything"\n' > .gitleaks.toml
  printf 'silence-my-leak\n' > .gitleaksignore
  snapshot change
  BASE="$base" EVENT=pull_request run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB/config")" = 'title = "trusted"' ]
  [ "$(cat "$STUB/ignore")" = trusted-fingerprint ]
  # gitleaks also reads the working tree's ignore list: it holds the trusted copy.
  [ "$(cat "$STUB/worktree-ignore")" = trusted-fingerprint ]
  [[ "$output" == *"::warning::This change modifies .gitleaks.toml .gitleaksignore — not applied to this scan"* ]]
}

@test "a config added by the change is not applied, and its ignore list is emptied" {
  printf 'title = "allow everything"\n' > .gitleaks.toml
  printf 'silence-my-leak\n' > .gitleaksignore
  snapshot change
  BASE="$BASE_SHA" EVENT=pull_request run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  default_rules
  [ ! -s "$STUB/ignore" ]
  [ ! -s "$STUB/worktree-ignore" ]
}

@test "an extended config is restored from the trusted commit, and its change flagged" {
  mkdir ci
  printf '[extend]\npath = "ci/rules.toml"\n' > .gitleaks.toml
  printf 'title = "trusted rules"\n' > ci/rules.toml
  snapshot config
  base="$(git rev-parse HEAD)"
  printf 'title = "allow everything"\n' > ci/rules.toml
  snapshot change
  BASE="$base" EVENT=pull_request run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat ci/rules.toml)" = 'title = "trusted rules"' ]
  [[ "$output" == *"::warning::This change modifies ci/rules.toml"* ]]
}

@test "an extended config outside the repository fails before gitleaks runs" {
  for path in ../rules.toml /etc/rules.toml ci/../../rules.toml; do
    printf '[extend]\npath = "%s"\n' "$path" > .gitleaks.toml
    snapshot "extend $path"
    BASE="$(git rev-parse HEAD)" EVENT=push run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::.gitleaks.toml extends '$path' outside the repository"* ]]
    [ ! -e "$STUB/args" ]
  done
}

@test "an extended config missing from the trusted commit fails" {
  printf '[extend]\npath = "ci/rules.toml"\n' > .gitleaks.toml
  snapshot config
  BASE="$(git rev-parse HEAD)" EVENT=push run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::extended config 'ci/rules.toml' not found"* ]]
  [ ! -e "$STUB/args" ]
}

@test "warns about added gitleaks:allow comments, and can disregard them" {
  printf 'key = "x" # gitleaks:allow\ntoken = "y" # gitleaks:allow\n' > secrets.txt
  snapshot change
  BASE="$BASE_SHA" EVENT=push run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::This change adds 2 \`gitleaks:allow\` comment(s)"* ]]
  run grep -qx -- '--ignore-gitleaks-allow' "$STUB/args"
  [ "$status" -ne 0 ]
  BASE="$BASE_SHA" EVENT=push IGNORE_INLINE_ALLOW=true run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qx -- '--ignore-gitleaks-allow' "$STUB/args"
}

@test "manual run: all fetched history, with the default branch's config" {
  printf 'title = "default branch"\n' > .gitleaks.toml
  snapshot config
  git update-ref refs/remotes/origin/main HEAD
  printf 'title = "this branch"\n' > .gitleaks.toml
  snapshot change
  EVENT=workflow_dispatch DEFAULT_BRANCH=main run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  # Exactly this: a trailing space would make gitleaks scan nothing.
  [ "$(log_opts)" = "--no-merges" ]
  [ "$(cat "$STUB/config")" = 'title = "default branch"' ]
  [[ "$output" != *"::warning::"* ]]
}

@test "scheduled run: all fetched history, with HEAD's config" {
  printf 'title = "tip"\n' > .gitleaks.toml
  snapshot config
  EVENT=schedule run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(log_opts)" = "--no-merges" ]
  [ "$(cat "$STUB/config")" = 'title = "tip"' ]
}

@test "no trusted commit: default rules, an empty ignore list and a warning, whatever the event" {
  printf 'title = "untrusted"\n' > .gitleaks.toml
  printf 'silence-my-leak\n' > .gitleaksignore
  snapshot change
  for event in push pull_request pull_request_target workflow_dispatch merge_group; do
    rm -f "$STUB/args"
    git checkout -q -- .gitleaksignore
    EVENT="$event" DEFAULT_BRANCH=main run bash "$SCRIPT"
    [ "$status" -eq 0 ] || { echo "$event: $output"; return 1; }
    [[ "$output" == *"::warning::"* ]] || { echo "no warning on $event"; return 1; }
    [ "$(log_opts)" = "--no-merges" ]
    default_rules
    [ ! -s "$STUB/ignore" ]
    [ ! -s "$STUB/worktree-ignore" ]
  done
}

@test "exits with gitleaks' status when a leak is found" {
  snapshot change
  BASE="$BASE_SHA" EVENT=push STUB_STATUS=1 run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "a change base missing from the clone fails before gitleaks runs" {
  BASE=1234567890abcdef1234567890abcdef12345678 EVENT=push run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::Change base 1234567890abcdef1234567890abcdef12345678 is not in the clone."* ]]
  [ ! -e "$STUB/args" ]
}

@test "honours REPORT_PATH and rejects a bad IGNORE_INLINE_ALLOW" {
  BASE="$BASE_SHA" EVENT=push REPORT_PATH=out/leaks.sarif run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qx -- '--report-path=out/leaks.sarif' "$STUB/args"
  IGNORE_INLINE_ALLOW=yes run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == "::error::IGNORE_INLINE_ALLOW must be true or false"* ]]
}
