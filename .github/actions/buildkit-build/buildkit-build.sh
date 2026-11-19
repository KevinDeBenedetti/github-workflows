#!/bin/sh
# Build and push an image with rootless BuildKit (buildctl-daemonless.sh),
# from this repository's git context at SHA, then write its digest to
# GITHUB_OUTPUT. POSIX sh: the moby/buildkit rootless image has busybox sh,
# no bash and no arrays.
#
# Credentials never reach the command line: the registry auth goes into a
# DOCKER_CONFIG file, the job token (BuildKit's GIT_AUTH_TOKEN, which fetches
# the git context) and each BUILD_SECRETS value into secret files, all in an
# owner-only directory removed on exit.
#
# Env: NAMES          image:tag list, comma-separated (image-tags `names`)
#      CACHE          registry layer-cache reference (image-tags `cache`)
#      LABELS         OCI labels, one KEY=VALUE per line (image-tags `labels`)
#      BUILD_ARGS     build args, one KEY=VALUE per line
#      BUILD_SECRETS  BuildKit secrets, one id=value per line
#      TARGET         Dockerfile stage, empty for the last one
#      PUSH           true | false
#      PROVENANCE     mode=max | mode=min | false
#      SBOM           true attaches an SBOM attestation
#      CONTEXT        context directory, relative to the repository root
#      DOCKERFILE     Dockerfile path, relative to CONTEXT
#      REGISTRY       registry host the token pushes to
#      REPO, SHA, SERVER_URL   the git context: <SERVER_URL>/<REPO>.git#<SHA>
#      GH_ACTOR, GH_TOKEN      registry login and git token
set -eu

# Credentials and secrets live in a private, job-scoped directory.
umask 077
WORK=$(mktemp -d "${TMPDIR:-/tmp}/buildkit.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# Registry auth (push + cache), read by buildctl from DOCKER_CONFIG.
export DOCKER_CONFIG="$WORK/docker"
mkdir -p "$DOCKER_CONFIG"
AUTH=$(printf '%s' "${GH_ACTOR}:${GH_TOKEN}" | base64 | tr -d '\n')
printf '{"auths":{"%s":{"auth":"%s"}}}' "$REGISTRY" "$AUTH" > "$DOCKER_CONFIG/config.json"

# Positional parameters hold the variable part of the command line, so every
# value stays ONE argument; no globbing of the values.
set -f
set --

# The git context is fetched by BuildKit with GIT_AUTH_TOKEN (the job token,
# contents: read) — passed as a secret, never as an opt.
printf '%s' "$GH_TOKEN" > "$WORK/git-token"
set -- "$@" --secret "id=GIT_AUTH_TOKEN,src=$WORK/git-token"

OLD_IFS="$IFS"
IFS='
'
# BUILD_SECRETS: one id=value per line → one secret file each.
for line in ${BUILD_SECRETS:-}; do
  [ -n "$line" ] || continue
  id="${line%%=*}"
  case "$id" in
    '' | *[!A-Za-z0-9_.-]*)
      echo "::error::invalid BUILD_SECRETS id (expected id=value lines)"
      exit 1
      ;;
  esac
  printf '%s' "${line#*=}" > "$WORK/secret-$id"
  set -- "$@" --secret "id=$id,src=$WORK/secret-$id"
done
# build-args: one KEY=VALUE per line.
for arg in ${BUILD_ARGS:-}; do
  if [ -n "$arg" ]; then
    set -- "$@" --opt "build-arg:$arg"
  fi
done
# OCI labels from the image-tags action: one KEY=VALUE per line.
for label in ${LABELS:-}; do
  set -- "$@" --opt "label:$label"
done
IFS="$OLD_IFS"

if [ -n "${TARGET:-}" ]; then
  set -- "$@" --opt "target=$TARGET"
fi
if [ "$PROVENANCE" != "false" ]; then
  set -- "$@" --opt "attest:provenance=$PROVENANCE"
fi
if [ "$SBOM" = "true" ]; then
  set -- "$@" --opt "attest:sbom="
fi

# Context = this repository at this exact commit, narrowed to the context
# directory (`#<ref>:<subdir>`); the Dockerfile path is relative to it.
SUBDIR="${CONTEXT#./}"
if [ "$SUBDIR" = "." ]; then SUBDIR=""; fi
GIT_CONTEXT="${SERVER_URL}/${REPO}.git#${SHA}${SUBDIR:+:$SUBDIR}"

buildctl-daemonless.sh build \
  --progress plain \
  --frontend dockerfile.v0 \
  --opt "context=${GIT_CONTEXT}" \
  --opt "filename=${DOCKERFILE}" \
  --import-cache "type=registry,ref=${CACHE}" \
  --export-cache "type=registry,ref=${CACHE},mode=max,ignore-error=true" \
  --output "type=image,\"name=${NAMES}\",push=${PUSH}" \
  --metadata-file "$WORK/metadata.json" \
  "$@"

DIGEST=$(sed -n 's/.*"containerimage\.digest": *"\(sha256:[0-9a-f]*\)".*/\1/p' "$WORK/metadata.json" | head -n 1)
echo "digest=${DIGEST}" >> "$GITHUB_OUTPUT"
