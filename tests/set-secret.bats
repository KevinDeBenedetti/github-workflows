#!/usr/bin/env bats
# Tests for scripts/set-secret.sh, with a fake gh on PATH.

SCRIPT="$BATS_TEST_DIRNAME/../scripts/set-secret.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p bin stub
  export STUB="$BATS_TEST_TMPDIR/stub"
  # The fake logs each call on one line of gh.log, and what `secret set` read
  # on stdin in stub/value-<owner>-<repo>. stub/variable is the
  # PROPAGATE_REPOSITORIES variable; a stub/fail-<owner>-<repo> file fails that
  # repository's `secret set`.
  cat > bin/gh << 'SH'
#!/usr/bin/env bash
echo "$*" >> "$STUB/gh.log"
case "$1 $2" in
  "repo view") echo me/hub ;;
  "variable get") cat "$STUB/variable" 2> /dev/null || { echo 'variable not found' >&2; exit 1; } ;;
  "secret set")
    slug="${5//\//-}"
    cat > "$STUB/value-$slug"
    [ ! -f "$STUB/fail-$slug" ] || { echo 'HTTP 403' >&2; exit 1; } ;;
  *) echo "unexpected gh call: $*" >&2; exit 99 ;;
esac
SH
  chmod +x bin/gh
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

sets() { grep '^secret set' "$STUB/gh.log" || true; }

@test "the value on stdin is set in each repository given, a bare name under the owner" {
  run bash "$SCRIPT" MY_TOKEN other/app site <<< 's3cret'
  [ "$status" -eq 0 ]
  [ "$(sets)" = "$(printf '%s\n' \
    'secret set MY_TOKEN --repo other/app' \
    'secret set MY_TOKEN --repo me/site')" ]
  [ "$(cat "$STUB/value-other-app")" = s3cret ]
  [ "$(cat "$STUB/value-me-site")" = s3cret ]
  [[ "$output" == *"✅ MY_TOKEN set in 2 repositories"* ]]
}

@test "the value never appears in the output or on a command line" {
  run bash "$SCRIPT" MY_TOKEN site <<< 's3cret'
  [ "$status" -eq 0 ]
  [[ "$output" != *s3cret* ]]
  ! grep -q s3cret "$STUB/gh.log"
}

@test "with no repository, this one and those of PROPAGATE_REPOSITORIES, branches dropped" {
  printf '%s\n' 'app:dev' '' 'other/infra' ' site ' > "$STUB/variable"
  run bash "$SCRIPT" MY_TOKEN <<< 's3cret'
  [ "$status" -eq 0 ]
  [ "$(sets)" = "$(printf '%s\n' \
    'secret set MY_TOKEN --repo me/hub' \
    'secret set MY_TOKEN --repo me/app' \
    'secret set MY_TOKEN --repo other/infra' \
    'secret set MY_TOKEN --repo me/site')" ]
}

@test "with no repository and no variable, this repository only" {
  run bash "$SCRIPT" MY_TOKEN <<< 's3cret'
  [ "$status" -eq 0 ]
  [ "$(sets)" = 'secret set MY_TOKEN --repo me/hub' ]
}

@test "an empty value is refused before any repository is touched" {
  run bash "$SCRIPT" MY_TOKEN site <<< ''
  [ "$status" -eq 1 ]
  [[ "$output" == *"the value is empty"* ]]
  [ -z "$(sets)" ]
}

@test "a failed repository is reported, the others are still set, and the exit code is 1" {
  touch "$STUB/fail-me-app"
  run bash "$SCRIPT" MY_TOKEN app site <<< 's3cret'
  [ "$status" -eq 1 ]
  [[ "$output" == *"❌ me/app: HTTP 403"* ]]
  [[ "$output" == *"✅ me/site"* ]]
  [ "$(cat "$STUB/value-me-site")" = s3cret ]
}

@test "a bad secret or repository name is refused" {
  run bash "$SCRIPT" 'my token' site <<< 's3cret'
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" MY_TOKEN 'a/b/c' <<< 's3cret'
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" MY_TOKEN '--repo' <<< 's3cret'
  [ "$status" -eq 2 ]
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [ ! -f "$STUB/gh.log" ] || [ -z "$(sets)" ]
}
