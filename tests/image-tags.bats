#!/usr/bin/env bats
# Tests for .github/actions/image-tags/image-tags.sh: the image name, tags and
# cache reference of cd-buildkit.yml and cd-docker.yml.

ROOT="$BATS_TEST_DIRNAME/.."
SCRIPT="$ROOT/.github/actions/image-tags/image-tags.sh"
SHA=0123456789abcdef0123456789abcdef01234567

setup() {
  cd "$BATS_TEST_TMPDIR"
  export OWNER=Owner REPO_NAME=App SHA DEFAULT_BRANCH=main GITHUB_OUTPUT="$BATS_TEST_TMPDIR/out"
  unset IMAGE_NAME VERSION TAG_LATEST REGISTRY REF_NAME REF_TYPE EVENT PR_NUMBER
  : > "$GITHUB_OUTPUT"
}

# out KEY: the single-line output KEY.
out() { sed -n "s/^$1=//p" "$GITHUB_OUTPUT"; }

@test "a push to a branch: sha, sanitised branch, lowercase image, cache" {
  EVENT=push REF_TYPE=branch REF_NAME=feat/New_thing run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(out image)" = ghcr.io/owner/app ]
  [ "$(out tags)" = "sha-0123456 feat-New_thing" ]
  [ "$(out names)" = "ghcr.io/owner/app:sha-0123456,ghcr.io/owner/app:feat-New_thing" ]
  [ "$(out cache)" = ghcr.io/owner/app-cache:buildcache ]
  [ "$(sed -n '/^raw-tags<</,/^RAW_TAGS_EOF$/p' "$GITHUB_OUTPUT")" = "$(printf '%s\n' 'raw-tags<<RAW_TAGS_EOF' \
    'type=raw,value=sha-0123456' 'type=raw,value=feat-New_thing' 'RAW_TAGS_EOF')" ]
}

@test "a pull request gets pr-<number>, no branch tag" {
  EVENT=pull_request REF_TYPE=branch REF_NAME=5/merge PR_NUMBER=5 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(out tags)" = "sha-0123456 pr-5" ]
}

@test "an explicit version adds itself and X.Y; latest only on the default branch; no duplicates" {
  EVENT=push REF_TYPE=branch REF_NAME=main VERSION=v1.4.2 TAG_LATEST=true IMAGE_NAME=Other REGISTRY=r.test run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(out image)" = r.test/owner/other ]
  [ "$(out tags)" = "sha-0123456 main v1.4.2 1.4 latest" ]

  : > "$GITHUB_OUTPUT"
  EVENT=push REF_TYPE=tag REF_NAME=v1.4.2 VERSION=1.4.2 TAG_LATEST=true run bash "$SCRIPT"
  [ "$(out tags)" = "sha-0123456 1.4.2 1.4" ]
}

@test "a push of each release tag of the vectors: X.Y.Z and X.Y, a pre-release alone, nothing else otherwise" {
  local tag kind
  while IFS=$'\t' read -r tag kind; do
    : > "$GITHUB_OUTPUT"
    EVENT=push REF_TYPE=tag REF_NAME="$tag" run bash "$SCRIPT"
    [ "$status" -eq 0 ] || { echo "$tag: $output"; return 1; }
    local version="${tag#v}" expected
    case "$kind" in
      release) expected="sha-0123456 ${version} $(printf '%s' "$version" | cut -d. -f1-2)" ;;
      prerelease) expected="sha-0123456 ${version}" ;;
      invalid) expected="sha-0123456" ;;
    esac
    [ "$(out tags)" = "$expected" ] || { echo "$tag ($kind): $(out tags)"; return 1; }
  done < <(grep -v '^#' "$BATS_TEST_DIRNAME/fixtures/release-tags.tsv")
}

@test "fails without an owner, a commit or a name" {
  OWNER='' run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  REPO_NAME='' run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::IMAGE_NAME or REPO_NAME is required"* ]]
}

@test "cleanup-ghcr.yml keeps the cache tag this script writes" {
  local tag
  tag="$(sed -n 's/^CACHE_TAG=//p' "$SCRIPT")"
  [ -n "$tag" ]
  grep -qE "^ +exclude-tags: ${tag}\$" "$ROOT/.github/workflows/cleanup-ghcr.yml"
}
