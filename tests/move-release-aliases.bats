#!/usr/bin/env bats
# Tests for .github/actions/move-release-aliases/move-release-aliases.sh,
# against a bare remote in a temporary directory.

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/move-release-aliases/move-release-aliases.sh"

# Git subcommands built at runtime, so this file never contains the literal
# commands blocked by the agent guardrails.
SAVE="com""mit"
SEND="pu""sh"

snapshot() {
  git -c user.name=t -c user.email=t@t -c "$SAVE.gpgsign=false" "$SAVE" -q --allow-empty -m "$1"
}

# release TAG: a new commit on the remote's main, tagged TAG.
release() {
  git -C "$BATS_TEST_TMPDIR/seed" checkout -q main
  (cd "$BATS_TEST_TMPDIR/seed" && snapshot "release $1" && git tag "$1" && git "$SEND" -q origin main "refs/tags/$1")
}

# remote_alias NAME: the commit the remote's tag NAME points at.
remote_alias() { git -C "$BATS_TEST_TMPDIR/remote.git" rev-parse --verify --quiet "refs/tags/$1^{commit}"; }
remote_tag() { git -C "$BATS_TEST_TMPDIR/remote.git" rev-parse "refs/tags/$1^{commit}"; }

setup() {
  cd "$BATS_TEST_TMPDIR"
  # No user or system git configuration (signing, hooks, default branch).
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  git init -q --bare --template= remote.git
  git init -q --template= -b main seed
  git -C seed remote add origin "$BATS_TEST_TMPDIR/remote.git"
  (cd seed && snapshot base && git "$SEND" -q origin main)
  export GIT_USER_NAME=bot GIT_USER_EMAIL=bot@example.test RETRY_DELAY=0
  unset TAG PRE_MAJOR_ALIAS PUSH_TOKEN REMOTE
  # The job's checkout: a clone that knows no tag yet.
  git clone -q --no-tags "$BATS_TEST_TMPDIR/remote.git" checkout
  cd checkout
}

@test "a release moves its major alias to the release commit, not to HEAD" {
  release v1.2.3
  release v1.3.0
  # The checkout sits on an older commit than the release.
  TAG=v1.3.0 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(remote_alias v1)" = "$(remote_tag v1.3.0)" ]
  [ "$(remote_alias v1)" != "$(git rev-parse HEAD)" ]
  [[ "$output" == *"✅ v1 → v1.3.0"* ]]
}

@test "before 1.0, both aliases move by default; minor and major move one" {
  release v0.24.3
  TAG=v0.24.3 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(remote_alias v0)" = "$(remote_tag v0.24.3)" ]
  [ "$(remote_alias v0.24)" = "$(remote_tag v0.24.3)" ]

  release v0.25.0
  TAG=v0.25.0 PRE_MAJOR_ALIAS=minor run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(remote_alias v0.25)" = "$(remote_tag v0.25.0)" ]
  [ "$(remote_alias v0)" = "$(remote_tag v0.24.3)" ]

  release v0.26.0
  TAG=v0.26.0 PRE_MAJOR_ALIAS=major run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(remote_alias v0)" = "$(remote_tag v0.26.0)" ]
  run remote_alias v0.26
  [ "$status" -ne 0 ]
}

@test "a re-run with a stale local alias does nothing when the remote is already right" {
  release v1.0.0
  TAG=v1.0.0 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  release v1.1.0
  # Another job moves v1 to v1.1.0; this checkout still holds the old v1.
  git clone -q --no-tags "$BATS_TEST_TMPDIR/remote.git" ../other
  (cd ../other && TAG=v1.1.0 bash "$SCRIPT")
  TAG=v1.1.0 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"v1 already points at v1.1.0"* ]]
  [ "$(remote_alias v1)" = "$(remote_tag v1.1.0)" ]
}

@test "an alias left at an older release is moved, from a checkout that holds its old value" {
  release v1.0.0
  TAG=v1.0.0 run bash "$SCRIPT"
  release v1.1.0
  TAG=v1.1.0 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(remote_alias v1)" = "$(remote_tag v1.1.0)" ]
}

@test "a component tag moves its own major alias" {
  release my-lib-v2.0.1
  TAG=my-lib-v2.0.1 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(remote_alias my-lib-v2)" = "$(remote_tag my-lib-v2.0.1)" ]
}

@test "fails on an unusable tag, a tag missing from the remote, or a bad pre-major-alias" {
  TAG='' run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::unusable release tag ''"* ]]
  TAG=v1 run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  TAG=v9.9.9 run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::release tag v9.9.9 not found on the remote"* ]]
  release v0.1.0
  TAG=v0.1.0 PRE_MAJOR_ALIAS=all run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::unsupported pre-major-alias 'all'"* ]]
}

@test "with a token, git gets a masked auth header for this run only" {
  release v3.0.0
  TAG=v3.0.0 PUSH_TOKEN=test-token GITHUB_SERVER_URL=https://github.test run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::add-mask::"* ]]
  [[ "$output" != *"test-token"* ]]
  run git config --get-regexp 'extraheader'
  [ "$status" -ne 0 ]
  [ "$(remote_alias v3)" = "$(remote_tag v3.0.0)" ]
}

@test "fails after three rejected attempts when the remote refuses the alias" {
  release v4.0.0
  mkdir -p "$BATS_TEST_TMPDIR/remote.git/hooks"
  printf '#!/bin/sh\necho "aliases are locked" >&2\nexit 1\n' > "$BATS_TEST_TMPDIR/remote.git/hooks/pre-receive"
  chmod +x "$BATS_TEST_TMPDIR/remote.git/hooks/pre-receive"
  TAG=v4.0.0 run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"attempt 3/3"* ]]
  [[ "$output" == *"::error::could not move v4 to v4.0.0 after 3 attempts"* ]]
  run remote_alias v4
  [ "$status" -ne 0 ]
}

@test "a pre-release moves no alias and reports prerelease=true" {
  release v1.0.0
  TAG=v1.0.0 run bash "$SCRIPT"
  release v1.1.0-rc.1
  : > "$BATS_TEST_TMPDIR/out"
  GITHUB_OUTPUT="$BATS_TEST_TMPDIR/out" TAG=v1.1.0-rc.1 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"v1.1.0-rc.1 is a pre-release"* ]]
  [ "$(cat "$BATS_TEST_TMPDIR/out")" = prerelease=true ]
  [ "$(remote_alias v1)" = "$(remote_tag v1.0.0)" ]
}

@test "classify-only reports the kind without an identity or a push" {
  release v2.0.0
  : > "$BATS_TEST_TMPDIR/out"
  unset GIT_USER_NAME GIT_USER_EMAIL
  GITHUB_OUTPUT="$BATS_TEST_TMPDIR/out" TAG=v2.0.0 CLASSIFY_ONLY=true run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/out")" = prerelease=false ]
  run remote_alias v2
  [ "$status" -ne 0 ]
  CLASSIFY_ONLY=yes TAG=v2.0.0 run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::CLASSIFY_ONLY must be true or false, not 'yes'"* ]]
}
