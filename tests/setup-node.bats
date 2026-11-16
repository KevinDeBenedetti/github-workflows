#!/usr/bin/env bats
# Tests for .github/actions/setup-node/resolve.sh, on throwaway project trees.

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/setup-node/resolve.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p apps/web
  unset DIR INPUT_PM INPUT_PNPM_VERSION INPUT_FRAMEWORK
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/out"
  : > "$GITHUB_OUTPUT"
}

# output_of KEY: the value the last run wrote for KEY.
output_of() { sed -n "s/^$1=//p" "$GITHUB_OUTPUT"; }

@test "no lockfile: pnpm, with its pinned version and commands" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_of pm)" = pnpm ]
  [[ "$(output_of pnpm-version)" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
  [ "$(output_of lockfile)" = pnpm-lock.yaml ]
  [ "$(output_of run-command)" = pnpm ]
  [ "$(output_of audit-command)" = "pnpm audit --audit-level=high" ]
}

@test "the lockfile picks the package manager and its commands" {
  touch bun.lock
  run bash "$SCRIPT"
  [ "$(output_of pm)" = bun ]
  [ "$(output_of lockfile)" = bun.lock ]
  [ "$(output_of run-command)" = "bun run" ]
  [ "$(output_of audit-command)" = "bun audit --audit-level=high" ]
  rm bun.lock && touch package-lock.json && : > "$GITHUB_OUTPUT"
  run bash "$SCRIPT"
  [ "$(output_of pm)" = npm ]
  [ "$(output_of run-command)" = "npm run" ]
  [ "$(output_of npm-lockfile)" = ./package-lock.json ]
  [ "$(output_of lockfile)" = package-lock.json ]
}

@test "a workspace member uses the root lockfile, its own first" {
  touch pnpm-lock.yaml
  DIR=apps/web run bash "$SCRIPT"
  [ "$(output_of pm)" = pnpm ]
  [ "$(output_of lockfile)" = pnpm-lock.yaml ]
  touch apps/web/bun.lockb && : > "$GITHUB_OUTPUT"
  DIR=apps/web run bash "$SCRIPT"
  [ "$(output_of pm)" = bun ]
  [ "$(output_of lockfile)" = apps/web/bun.lockb ]
}

@test "npm runs its install from the lockfile's directory" {
  touch package-lock.json
  DIR=apps/web run bash "$SCRIPT"
  [ "$(output_of pm)" = npm ]
  [ "$(output_of npm-dir)" = . ]
  [ "$(output_of npm-lockfile)" = ./package-lock.json ]
}

@test "a forced package manager wins over the lockfile; npm without a lockfile fails" {
  touch bun.lock
  INPUT_PM=pnpm run bash "$SCRIPT"
  [ "$(output_of pm)" = pnpm ]
  rm bun.lock
  INPUT_PM=npm run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::package-manager npm needs a package-lock.json"* ]]
  INPUT_PM=yarn run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::unsupported package-manager 'yarn'"* ]]
}

@test "pnpm version: the input, else packageManager, else the pinned release" {
  INPUT_PNPM_VERSION=9.1.0 run bash "$SCRIPT"
  [ "$(output_of pnpm-version)" = 9.1.0 ]
  printf '{"packageManager": "pnpm@10.2.0"}\n' > apps/web/package.json
  : > "$GITHUB_OUTPUT"
  DIR=apps/web run bash "$SCRIPT"
  [ "$(output_of pnpm-version)" = "" ]
  [ "$(output_of package-json)" = apps/web/package.json ]
}

@test "framework: detected from the config files, or forced" {
  DIR=apps/web run bash "$SCRIPT"
  [ "$(output_of framework)" = vite ]
  [ "$(output_of build-output)" = dist ]
  touch apps/web/next.config.mjs && : > "$GITHUB_OUTPUT"
  DIR=apps/web run bash "$SCRIPT"
  [ "$(output_of framework)" = next ]
  [ "$(output_of build-output)" = .next ]
  : > "$GITHUB_OUTPUT"
  DIR=apps/web INPUT_FRAMEWORK=nuxt run bash "$SCRIPT"
  [ "$(output_of framework)" = nuxt ]
  [ "$(output_of build-output)" = .output ]
  DIR=apps/web INPUT_FRAMEWORK=astro run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::unsupported framework 'astro'"* ]]
}
