#!/usr/bin/env bash
# Image name, tags and layer-cache reference of a build, for cd-buildkit.yml
# (both build jobs) and cd-docker.yml, so every image workflow tags alike.
#
# Tags, a subset of docker/metadata-action's defaults:
#   sha-<7>        always
#   <branch>       a push to a branch, sanitised (/ → -, 128 characters)
#   pr-<number>    a pull request
#   X.Y.Z, X.Y     a push of a release tag vX.Y.Z (X.Y.Z-pre: that tag only)
#   VERSION, X.Y   an explicit version (v1.2.3 → v1.2.3 and 1.2; a
#                  pre-release keeps its own tag only: X.Y is the finals')
#   latest         TAG_LATEST=true on the default branch
# A version that is not [v]X.Y.Z[-pre] is tagged as given, with no X.Y.
# tests/fixtures/release-tags.tsv holds the tags this rule is tested against.
#
# Environment: IMAGE_NAME (default: REPO_NAME), REPO_NAME, OWNER, SHA,
# REF_NAME, REF_TYPE, EVENT, PR_NUMBER, DEFAULT_BRANCH, VERSION, TAG_LATEST,
# REGISTRY (default ghcr.io), GITHUB_OUTPUT.
#
# Outputs: image (registry/owner/name, lowercase), tags (space-separated),
# names (image:tag, comma-separated), raw-tags (one `type=raw,value=` line per
# tag, for metadata-action), cache (<image>-cache:buildcache).
set -euo pipefail

# The tag of the layer cache, which cleanup-ghcr.yml keeps.
CACHE_TAG=buildcache
# An explicit version may omit the v; a release tag may not (vX.Y.Z[-pre],
# like every release-tag rule of this repository).
release_re='^v?([0-9]+)\.([0-9]+)\.[0-9]+(-[0-9A-Za-z.-]+)?$'
tag_re='^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'

fail() {
  echo "::error::$*" >&2
  exit 1
}

: "${OWNER:?OWNER is required}"
: "${SHA:?SHA is required}"
name="${IMAGE_NAME:-${REPO_NAME:-}}"
[[ -n "$name" ]] || fail "IMAGE_NAME or REPO_NAME is required"
# OCI repositories must be lowercase.
image="$(printf '%s/%s/%s' "${REGISTRY:-ghcr.io}" "$OWNER" "$name" | tr '[:upper:]' '[:lower:]')"

tags=()
add_tag() {
  local tag
  for tag in "${tags[@]}"; do
    [[ "$tag" == "$1" ]] && return 0
  done
  tags+=("$1")
}
# add_version VERSION: the version, then X.Y for a final release.
add_version() {
  add_tag "$1"
  if [[ "$1" =~ $release_re && -z "${BASH_REMATCH[3]}" ]]; then
    add_tag "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
  fi
}

add_tag "sha-${SHA:0:7}"
if [[ "${EVENT:-}" == push && "${REF_TYPE:-}" == branch ]]; then
  branch="$(printf '%s' "${REF_NAME:-}" | tr -c 'A-Za-z0-9_.-' '-' | sed 's/^[.-]*//' | cut -c1-128)"
  [[ -z "$branch" ]] || add_tag "$branch"
fi
if [[ "${EVENT:-}" == pull_request && -n "${PR_NUMBER:-}" ]]; then
  add_tag "pr-${PR_NUMBER}"
fi
if [[ "${EVENT:-}" == push && "${REF_TYPE:-}" == tag && "${REF_NAME:-}" =~ $tag_re ]]; then
  add_version "${REF_NAME#v}"
fi
if [[ -n "${VERSION:-}" ]]; then
  add_version "$VERSION"
fi
if [[ "${TAG_LATEST:-false}" == true && -n "${REF_NAME:-}" && "${REF_NAME:-}" == "${DEFAULT_BRANCH:-}" ]]; then
  add_tag latest
fi

names=""
raw=""
for tag in "${tags[@]}"; do
  names="${names:+$names,}${image}:${tag}"
  raw+="type=raw,value=${tag}"$'\n'
done

echo "Image: ${image}"
echo "Tags:  ${tags[*]}"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "image=${image}"
    echo "tags=${tags[*]}"
    echo "names=${names}"
    echo "cache=${image}-cache:${CACHE_TAG}"
    echo "raw-tags<<RAW_TAGS_EOF"
    printf '%s' "$raw"
    echo "RAW_TAGS_EOF"
  } >> "$GITHUB_OUTPUT"
fi
