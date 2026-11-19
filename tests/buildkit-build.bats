#!/usr/bin/env bats
# Tests for .github/actions/buildkit-build/buildkit-build.sh, run with dash
# (the rootless BuildKit image has busybox sh, no bash) and a fake
# buildctl-daemonless.sh on PATH.

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/buildkit-build/buildkit-build.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p bin seen
  export SEEN="$BATS_TEST_TMPDIR/seen"
  # The fake records its arguments, one per line, copies the files it was
  # handed (they are deleted once the script exits), and writes the build
  # metadata unless $BUILD_FAILS is set.
  cat > bin/buildctl-daemonless.sh << 'SH'
#!/bin/sh
printf '%s\n' "$@" > "$SEEN/args"
cp "$DOCKER_CONFIG/config.json" "$SEEN/docker-config.json"
work=$(dirname "$DOCKER_CONFIG")
ls -l "$work" > "$SEEN/modes"
for f in "$work"/git-token "$work"/secret-*; do
  [ -f "$f" ] && cp "$f" "$SEEN/"
done
[ -z "${BUILD_FAILS:-}" ] || exit 1
while [ "$#" -gt 0 ]; do
  if [ "$1" = --metadata-file ]; then
    printf '{\n  "containerimage.digest": "sha256:abc123",\n  "image.name": "x"\n}\n' > "$2"
  fi
  shift
done
SH
  chmod +x bin/buildctl-daemonless.sh
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export TMPDIR="$BATS_TEST_TMPDIR"
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/output"
  : > "$GITHUB_OUTPUT"
  export NAMES='ghcr.io/o/app:sha-1234567,ghcr.io/o/app:main'
  export CACHE='ghcr.io/o/app-cache:buildcache'
  export REGISTRY=ghcr.io CONTEXT=. DOCKERFILE=Dockerfile PUSH=true
  export PROVENANCE=mode=max SBOM=true
  export REPO=o/app SHA=0123456789abcdef SERVER_URL=https://github.com
  export GH_ACTOR=octocat GH_TOKEN=job-token
  unset LABELS BUILD_ARGS BUILD_SECRETS TARGET BUILD_FAILS
}

args() { cat "$SEEN/args"; }

@test "the command line: context, caches, output, attestations and the git token" {
  run dash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(args)" = "$(printf '%s\n' build --progress plain --frontend dockerfile.v0 \
    --opt 'context=https://github.com/o/app.git#0123456789abcdef' \
    --opt filename=Dockerfile \
    --import-cache 'type=registry,ref=ghcr.io/o/app-cache:buildcache' \
    --export-cache 'type=registry,ref=ghcr.io/o/app-cache:buildcache,mode=max,ignore-error=true' \
    --output 'type=image,"name=ghcr.io/o/app:sha-1234567,ghcr.io/o/app:main",push=true' \
    --metadata-file "$(sed -n '/^--metadata-file$/{n;p;}' "$SEEN/args")" \
    --secret "id=GIT_AUTH_TOKEN,src=$(sed -n 's/^id=GIT_AUTH_TOKEN,src=//p' "$SEEN/args")" \
    --opt attest:provenance=mode=max --opt attest:sbom=)" ]
  [ "$(cat "$GITHUB_OUTPUT")" = 'digest=sha256:abc123' ]
}

@test "a context directory narrows the git context; target, no push, no attestations" {
  CONTEXT=./services/api TARGET=prod PUSH=false PROVENANCE=false SBOM=false run dash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qx 'context=https://github.com/o/app.git#0123456789abcdef:services/api' "$SEEN/args"
  grep -qx 'type=image,"name=ghcr.io/o/app:sha-1234567,ghcr.io/o/app:main",push=false' "$SEEN/args"
  grep -qx 'target=prod' "$SEEN/args"
  ! grep -q '^attest:' "$SEEN/args"
}

@test "each build-arg and label line is one argument, spaces and globs kept" {
  touch match-me
  BUILD_ARGS=$'NODE_ENV=production\n\nGREETING=hello world\nPATTERN=*' \
    LABELS=$'org.opencontainers.image.title=app\norg.opencontainers.image.description=An app, with * and spaces' \
    run dash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(grep -A1 -x -- --opt "$SEEN/args" | grep -E '^(build-arg|label):')" = "$(printf '%s\n' \
    build-arg:NODE_ENV=production 'build-arg:GREETING=hello world' 'build-arg:PATTERN=*' \
    label:org.opencontainers.image.title=app \
    'label:org.opencontainers.image.description=An app, with * and spaces')" ]
}

@test "secrets reach BuildKit as private files, never on the command line" {
  BUILD_SECRETS=$'NPM_TOKEN=npm-secret\n\nDB_URL=postgres://u:p@h/db?a=b' run dash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$SEEN/secret-NPM_TOKEN")" = npm-secret ]
  [ "$(cat "$SEEN/secret-DB_URL")" = 'postgres://u:p@h/db?a=b' ]
  [ "$(cat "$SEEN/git-token")" = job-token ]
  grep -qE '^id=NPM_TOKEN,src=.*/secret-NPM_TOKEN$' "$SEEN/args"
  grep -qE '^id=DB_URL,src=.*/secret-DB_URL$' "$SEEN/args"
  ! grep -qE 'npm-secret|postgres|job-token' "$SEEN/args"
  # The registry auth is actor:token, base64-encoded.
  [ "$(jq -r '.auths["ghcr.io"].auth' "$SEEN/docker-config.json" | base64 -d)" = octocat:job-token ]
  # Owner-only files, deleted once the step ends.
  ! grep -E '^-' "$SEEN/modes" | grep -vq '^-rw-------'
  [ -z "$(ls "$BATS_TEST_TMPDIR" | grep -v -e bin -e seen -e output -e match-me)" ]
}

@test "a secret line without a usable id fails before BuildKit runs" {
  BUILD_SECRETS=$'GOOD=1\n=no-id' run dash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::invalid BUILD_SECRETS id (expected id=value lines)"* ]]
  [ ! -f "$SEEN/args" ]
  BUILD_SECRETS='bad id=1' run dash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "a failed build fails the step, with no digest" {
  BUILD_FAILS=1 run dash "$SCRIPT"
  [ "$status" -eq 1 ]
  [ ! -s "$GITHUB_OUTPUT" ]
}
