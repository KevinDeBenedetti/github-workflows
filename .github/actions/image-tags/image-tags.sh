#!/usr/bin/env bash
# Image name, tags and layer-cache reference of a build, for cd-docker.yml.
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
# OCI labels (org.opencontainers.image.*), the keys docker/metadata-action
# sets, so an image carries the same labels whichever path built it:
#   title        the image name, as given
#   description  the repository's description (left out when empty)
#   url, source  the repository's page
#   version      the most specific tag: the explicit version, the release
#                tag's X.Y.Z, pr-<number>, the branch, else sha-<7>
#   created      the build time (UTC)
#   revision     the commit
#   licenses     the repository's SPDX licence (left out when empty or
#                NOASSERTION)
# A value is one line: control characters become spaces.
#
# Environment: IMAGE_NAME (default: REPO_NAME), REPO_NAME, OWNER, SHA,
# REF_NAME, REF_TYPE, EVENT, PR_NUMBER, DEFAULT_BRANCH, VERSION, TAG_LATEST,
# REGISTRY (default ghcr.io), SERVER_URL, REPOSITORY (owner/name),
# DESCRIPTION, LICENSE, GITHUB_OUTPUT.
#
# Outputs: image (registry/owner/name, lowercase), tags (space-separated),
# names (image:tag, comma-separated), raw-tags (one `type=raw,value=` line per
# tag, for metadata-action), cache (<image>-cache:buildcache), labels (one
# KEY=VALUE line per label).
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

# version: the label of the most specific tag, each rule below overriding
# the one before.
add_tag "sha-${SHA:0:7}"
version="sha-${SHA:0:7}"
if [[ "${EVENT:-}" == push && "${REF_TYPE:-}" == branch ]]; then
  branch="$(printf '%s' "${REF_NAME:-}" | tr -c 'A-Za-z0-9_.-' '-' | sed 's/^[.-]*//' | cut -c1-128)"
  if [[ -n "$branch" ]]; then
    add_tag "$branch"
    version="$branch"
  fi
fi
if [[ "${EVENT:-}" == pull_request && -n "${PR_NUMBER:-}" ]]; then
  add_tag "pr-${PR_NUMBER}"
  version="pr-${PR_NUMBER}"
fi
if [[ "${EVENT:-}" == push && "${REF_TYPE:-}" == tag && "${REF_NAME:-}" =~ $tag_re ]]; then
  add_version "${REF_NAME#v}"
  version="${REF_NAME#v}"
fi
if [[ -n "${VERSION:-}" ]]; then
  add_version "$VERSION"
  version="$VERSION"
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

# one_line TEXT: TEXT with its control characters turned into spaces.
one_line() { printf '%s' "$1" | tr '\000-\037\177' ' '; }
repo_url="${SERVER_URL:-https://github.com}/${REPOSITORY:-${OWNER}/${REPO_NAME:-$name}}"
labels="org.opencontainers.image.title=$(one_line "$name")"$'\n'
if [[ -n "${DESCRIPTION:-}" ]]; then
  labels+="org.opencontainers.image.description=$(one_line "$DESCRIPTION")"$'\n'
fi
labels+="org.opencontainers.image.url=$(one_line "$repo_url")"$'\n'
labels+="org.opencontainers.image.source=$(one_line "$repo_url")"$'\n'
labels+="org.opencontainers.image.version=$(one_line "$version")"$'\n'
labels+="org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"$'\n'
labels+="org.opencontainers.image.revision=${SHA}"$'\n'
if [[ -n "${LICENSE:-}" && "${LICENSE}" != NOASSERTION ]]; then
  labels+="org.opencontainers.image.licenses=$(one_line "$LICENSE")"$'\n'
fi

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
    # Every line starts with org.opencontainers.: none can be the delimiter.
    echo "labels<<LABELS_EOF"
    printf '%s' "$labels"
    echo "LABELS_EOF"
  } >> "$GITHUB_OUTPUT"
fi
