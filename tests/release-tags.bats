#!/usr/bin/env bats
# Every release-tag rule of this repository against the same tags,
# tests/fixtures/release-tags.tsv: each rule reads the tag its own way, and
# this file keeps them in agreement on which tags are releases, pre-releases
# or unusable.

ACTIONS="$BATS_TEST_DIRNAME/../.github/actions"
VECTORS="$BATS_TEST_DIRNAME/fixtures/release-tags.tsv"
SHA=1111111111111111111111111111111111111111

# vectors: "TAG KIND" lines, comments left out.
vectors() { grep -v '^#' "$VECTORS"; }

setup() {
  cd "$BATS_TEST_TMPDIR"
  unset GITHUB_OUTPUT
}

@test "the vectors cover the three kinds" {
  for kind in release prerelease invalid; do
    vectors | cut -f2 | grep -qx "$kind"
  done
  # Nothing but the three kinds.
  [ -z "$(vectors | cut -f2 | grep -vxE 'release|prerelease|invalid')" ]
}

@test "move-release-aliases.sh classifies every tag" {
  local tag kind
  while IFS=$'\t' read -r tag kind; do
    : > out
    GITHUB_OUTPUT=out TAG="$tag" CLASSIFY_ONLY=true run bash "$ACTIONS/move-release-aliases/move-release-aliases.sh"
    case "$kind" in
      invalid)
        [ "$status" -eq 1 ] || { echo "accepted $tag"; return 1; }
        [[ "$output" == *"::error::unusable release tag '$tag'"* ]]
        ;;
      release)
        [ "$status" -eq 0 ] || { echo "refused $tag: $output"; return 1; }
        [ "$(cat out)" = prerelease=false ] || { echo "$tag: $(cat out)"; return 1; }
        ;;
      prerelease)
        [ "$status" -eq 0 ] || { echo "refused $tag: $output"; return 1; }
        [ "$(cat out)" = prerelease=true ] || { echo "$tag: $(cat out)"; return 1; }
        ;;
    esac
  done < <(vectors)
}

@test "propagate-release.sh refuses exactly the invalid tags" {
  local tag kind
  while IFS=$'\t' read -r tag kind; do
    # No network: an accepted tag stops at the first API call, on a dead host.
    TAG="$tag" SOURCE=o/src REPOSITORIES=app GITHUB_TOKEN=t GITHUB_API_URL=http://127.0.0.1:9 \
      GITHUB_GRAPHQL_URL=http://127.0.0.1:9/graphql GITHUB_SERVER_URL=http://127.0.0.1:9 \
      run bash "$ACTIONS/propagate-release/propagate-release.sh"
    if [ "$kind" = invalid ]; then
      [[ "$output" == *"TAG must be a release vX.Y.Z, not '$tag'"* ]] || { echo "accepted $tag"; return 1; }
    else
      [[ "$output" != *"TAG must be a release"* ]] || { echo "refused $tag"; return 1; }
    fi
  done < <(vectors)
}

@test "bump-pins.py refuses exactly the invalid tags" {
  local tag kind
  : > w.yml
  while IFS=$'\t' read -r tag kind; do
    run python3 "$ACTIONS/propagate-release/bump-pins.py" o/src "$tag" "$SHA" w.yml
    if [ "$kind" = invalid ]; then
      [ "$status" -eq 2 ] || { echo "accepted $tag"; return 1; }
    else
      [ "$status" -eq 0 ] || { echo "refused $tag: $output"; return 1; }
    fi
  done < <(vectors)
}
