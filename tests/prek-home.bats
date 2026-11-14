#!/usr/bin/env bats
# Tests for .github/actions/prek-home/prek-home.sh

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/prek-home/prek-home.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p bin root repo
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  # macOS has no flock(1): a stand-in for its fd form (`flock [-s|-x][-n] FD`)
  # making the same flock(2) call, so the lock outlives it like the real one.
  if ! command -v flock >/dev/null; then
    cat >bin/flock <<'PY'
#!/usr/bin/env python3
import fcntl, sys
mode, fd = fcntl.LOCK_EX, None
for arg in sys.argv[1:]:
    if arg.startswith("-"):
        for flag in arg[1:]:
            mode = {"s": mode & ~fcntl.LOCK_EX | fcntl.LOCK_SH,
                    "x": mode & ~fcntl.LOCK_SH | fcntl.LOCK_EX,
                    "n": mode | fcntl.LOCK_NB}[flag]
    else:
        fd = int(arg)
try:
    fcntl.flock(fd, mode)
except BlockingIOError:
    sys.exit(1)
PY
    chmod +x bin/flock
  fi
  export PREK_HOME_ROOT="$BATS_TEST_TMPDIR/root" CONFIG_DIR="$BATS_TEST_TMPDIR/repo" PREK_VERSION=0.4.12
  export RUNNER_OS=Linux RUNNER_ARCH=X64
  export GITHUB_ENV="$BATS_TEST_TMPDIR/env" GITHUB_OUTPUT="$BATS_TEST_TMPDIR/output"
  : >"$GITHUB_ENV"
  : >"$GITHUB_OUTPUT"
  unset MAX_AGE_DAYS
  echo 'repos = []' >repo/prek.toml
}

# refute CMD...: fails the test when CMD succeeds. A bare `! CMD` in the middle
# of a test never fails it: bash's errexit ignores negated commands.
refute() {
  if "$@"; then
    echo "unexpected success: $*" >&2
    return 1
  fi
}

# store: the store `select` exports, read from GITHUB_ENV.
store() {
  sed -n 's/^PREK_HOME=//p' "$GITHUB_ENV" | tail -n 1
}

# select_key: run `select` and print the store's key.
select_key() {
  bash "$SCRIPT" select >/dev/null
  basename "$(store)"
}

# age PATH DAYS: set PATH's modification time DAYS days back.
age() {
  python3 -c 'import os, sys, time; t = time.time() - float(sys.argv[2]) * 86400; os.utime(sys.argv[1], (t, t))' "$1" "$2"
}

# old_store KEY DAYS: a store and its lock file, last used DAYS days ago.
old_store() {
  mkdir -p "root/$1/hooks"
  echo env >"root/$1/hooks/file"
  touch "root/$1.lock"
  age "root/$1.lock" "$2"
}

@test "select exports PREK_HOME to a new store of this config under prek-home" {
  run bash "$SCRIPT" select
  [ "$status" -eq 0 ]
  local store
  store="$(store)"
  [[ "$store" =~ ^$PREK_HOME_ROOT/[0-9a-f]{16}$ ]]
  [ -d "$store" ]
  [ -f "$store.lock" ]
  grep -qx "path=$store" "$GITHUB_OUTPUT"
  [ "$output" = "prek store $store (new: this run installs every hook environment)." ]

  run bash "$SCRIPT" select
  [ "$output" = "prek store $store (reusing the hook environments of earlier runs)." ]
}

@test "the store key follows the configs, the prek release and the platform" {
  local base
  base="$(select_key)"
  [ "$(select_key)" = "$base" ]

  # Files that are not prek configs, and configs under .git or node_modules, do not count.
  echo x >repo/README.md
  mkdir -p repo/node_modules/dep repo/.git
  echo 'repos = []' >repo/node_modules/dep/prek.toml
  echo 'repos = []' >repo/.git/prek.toml
  [ "$(select_key)" = "$base" ]

  echo '# changed' >>repo/prek.toml
  local changed
  changed="$(select_key)"
  [ "$changed" != "$base" ]

  mkdir -p repo/sub
  echo 'repos: []' >repo/sub/.pre-commit-config.yaml
  [ "$(select_key)" != "$changed" ]

  local keys=()
  keys+=("$(PREK_VERSION=0.5.0 select_key)")
  keys+=("$(RUNNER_ARCH=ARM64 select_key)")
  keys+=("$(RUNNER_OS=macOS select_key)")
  [ "$(printf '%s\n' "${keys[@]}" | sort -u | wc -l)" -eq 3 ]
}

@test "prek-home must be an absolute, writable directory" {
  for path in relative/dir '' ./root; do
    PREK_HOME_ROOT="$path" run bash "$SCRIPT" select
    [ "$status" -eq 1 ]
    [ "$output" = "::error::prek-home must be an absolute path (got '$path')" ]
  done

  PREK_HOME_ROOT=/ run bash "$SCRIPT" select
  [ "$status" -eq 1 ]
  [ "$output" = "::error::prek-home must be a directory of its own, not /" ]

  PREK_HOME_ROOT="$BATS_TEST_TMPDIR/missing" run bash "$SCRIPT" clean
  [ "$status" -eq 1 ]
  [[ "$output" == "::error::prek-home $BATS_TEST_TMPDIR/missing is not a directory: mount a volume there"* ]]

  # A trailing slash is the same directory.
  PREK_HOME_ROOT="$PREK_HOME_ROOT/" run bash "$SCRIPT" select
  [ "$status" -eq 0 ]
  [[ "$(store)" =~ ^$PREK_HOME_ROOT/[0-9a-f]{16}$ ]]

  [ -s "$GITHUB_ENV" ]
}

@test "select needs a prek version and an existing working directory" {
  PREK_VERSION='' run bash "$SCRIPT" select
  [ "$status" -eq 1 ]
  [ "$output" = "::error::prek-version is empty" ]

  CONFIG_DIR="$BATS_TEST_TMPDIR/nowhere" run bash "$SCRIPT" select
  [ "$status" -eq 1 ]
  [ "$output" = "::error::working-directory $BATS_TEST_TMPDIR/nowhere does not exist" ]
  [ ! -s "$GITHUB_ENV" ]

  run bash "$SCRIPT" other
  [ "$status" -eq 1 ]
  [ "$output" = "::error::usage: prek-home.sh select|clean (got 'other')" ]
}

@test "clean deletes the stores unused for over 14 days and keeps the others" {
  old_store aaaaaaaaaaaaaaaa 15
  old_store bbbbbbbbbbbbbbbb 13
  old_store cccccccccccccccc 400
  # Not a store of select: never touched, however old.
  mkdir -p root/lost+found root/other-tool
  age root/other-tool 400

  run bash "$SCRIPT" clean
  [ "$status" -eq 0 ]
  [ ! -e root/aaaaaaaaaaaaaaaa ] && [ ! -e root/aaaaaaaaaaaaaaaa.lock ]
  [ ! -e root/cccccccccccccccc ] && [ ! -e root/cccccccccccccccc.lock ]
  [ -f root/bbbbbbbbbbbbbbbb/hooks/file ] && [ -f root/bbbbbbbbbbbbbbbb.lock ]
  [ -d root/lost+found ] && [ -d root/other-tool ]
  [[ "$output" == *"Deleted the prek store $PREK_HOME_ROOT/aaaaaaaaaaaaaaaa, unused for over 14 days."* ]]
  [[ "$output" == *"prek stores in $PREK_HOME_ROOT: 2 deleted, 1 kept; "*" free of "* ]]
}

@test "clean follows max-age-days and rejects a bad value" {
  old_store aaaaaaaaaaaaaaaa 3
  MAX_AGE_DAYS=7 run bash "$SCRIPT" clean
  [ -d root/aaaaaaaaaaaaaaaa ]
  MAX_AGE_DAYS=2 run bash "$SCRIPT" clean
  [ ! -e root/aaaaaaaaaaaaaaaa ]

  for days in 0 -1 1.5 abc 10000; do
    MAX_AGE_DAYS="$days" run bash "$SCRIPT" clean
    [ "$status" -eq 1 ]
    [ "$output" = "::error::max-age-days must be a whole number from 1 to 9999 (got '$days')" ]
  done
}

@test "clean keeps a stale store whose lock a run holds" {
  old_store aaaaaaaaaaaaaaaa 30
  exec 8>>root/aaaaaaaaaaaaaaaa.lock
  flock -s 8
  run bash "$SCRIPT" clean
  exec 8>&-
  [ "$status" -eq 0 ]
  [ -f root/aaaaaaaaaaaaaaaa/hooks/file ]
  [[ "$output" == *"0 deleted, 1 kept"* ]]
}

@test "select waits for a cleanup of its store, not for another run of it" {
  bash "$SCRIPT" select >/dev/null
  local store pid
  store="$(store)"

  # Another run's shared lock: select goes ahead.
  exec 8>>"$store.lock"
  flock -s 8
  run bash "$SCRIPT" select 8>&-
  exec 8>&-
  [ "$status" -eq 0 ]

  # A cleanup's exclusive lock: select waits until it is released. The
  # background select must not inherit fd 8, or it would hold the lock itself.
  exec 8>>"$store.lock"
  flock -x 8
  bash "$SCRIPT" select >select.out 2>&1 8>&- &
  pid=$!
  sleep 1
  kill -0 "$pid"
  exec 8>&-
  wait "$pid"
  [[ "$(cat select.out)" == "prek store $store ("* ]]
}

@test "clean empties a read-only tree, like Go's module cache" {
  old_store aaaaaaaaaaaaaaaa 30
  mkdir -p root/aaaaaaaaaaaaaaaa/go/pkg/mod/x@v1
  echo code >root/aaaaaaaaaaaaaaaa/go/pkg/mod/x@v1/x.go
  chmod -R a-w root/aaaaaaaaaaaaaaaa/go
  run bash "$SCRIPT" clean
  [ "$status" -eq 0 ]
  [ ! -e root/aaaaaaaaaaaaaaaa ]
}

@test "clean gives a store without a lock file a fresh countdown" {
  mkdir -p root/aaaaaaaaaaaaaaaa
  age root/aaaaaaaaaaaaaaaa 30
  run bash "$SCRIPT" clean
  [ "$status" -eq 0 ]
  [ -d root/aaaaaaaaaaaaaaaa ] && [ -f root/aaaaaaaaaaaaaaaa.lock ]
  refute [ -n "$(find root/aaaaaaaaaaaaaaaa.lock -mmin +60)" ]
}

@test "select keeps its own store out of the cleanup: it was just used" {
  bash "$SCRIPT" select >/dev/null
  local store
  store="$(store)"
  age "$store.lock" 30
  bash "$SCRIPT" select >/dev/null
  run bash "$SCRIPT" clean
  [ -d "$store" ]
  [[ "$output" == *"0 deleted, 1 kept"* ]]
}
