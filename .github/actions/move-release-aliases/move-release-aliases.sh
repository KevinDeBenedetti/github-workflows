#!/usr/bin/env bash
# Move the alias tags of a release: v1.2.3 also moves v1, so callers pinned to
# @v1 receive it.
#
# Before 1.0 (PRE_MAJOR_ALIAS): semver gives no stability promise inside 0.x
# and release-please (with bump-minor-pre-major) ships breaking changes as
# minor bumps, so a moving `v0` carries callers across them. `minor` moves only
# v0.<minor> (v0.24.3 → v0.24); `major` only v0; `both` moves both. A
# component tag follows the same rule under its prefix (my-lib-v0.3.1 →
# my-lib-v0, my-lib-v0.3).
#
# Why this is more than `git tag -f` and a forced push: pushing a tag is a
# compare-and-swap against the value the *local* clone believes the remote
# holds, and `--force` waives the fast-forward requirement, not that check. So
# a job whose checkout predates a successful move fails with `cannot lock ref
# 'refs/tags/vN': is at X but expected Y`, which is what a re-run of an already
# released run does, every time. Hence: re-sync each alias from the remote, do
# nothing when it is already right, and only then move it, retrying when a
# concurrent job moved it in between.
#
# A semver pre-release (v1.3.0-rc.2, my-lib-v1.3.0-beta.1) moves no alias: v1
# would otherwise point at a release candidate. The script reports the kind as
# `prerelease=true|false` in GITHUB_OUTPUT, and with CLASSIFY_ONLY=true does
# only that (no git, no identity needed). tests/fixtures/release-tags.tsv
# holds the tags every release-tag rule of this repository is tested against.
#
# Environment:
#   TAG              the release tag, [component-]vMAJOR.MINOR.PATCH[-pre] (required)
#   CLASSIFY_ONLY    true: report prerelease and stop (default false)
#   PRE_MAJOR_ALIAS  both | minor | major (default both), for v0.x releases
#   GIT_USER_NAME, GIT_USER_EMAIL  identity of the alias tags (required)
#   PUSH_TOKEN       token for the push; empty uses git's own credentials
#   GITHUB_SERVER_URL  set by the runner (with PUSH_TOKEN)
#   REMOTE           remote to move the aliases on (default origin)
#   RETRY_DELAY      seconds between two attempts (default 3)
set -euo pipefail

TAG="${TAG:-}"
CLASSIFY_ONLY="${CLASSIFY_ONLY:-false}"
PRE_MAJOR_ALIAS="${PRE_MAJOR_ALIAS:-both}"
REMOTE="${REMOTE:-origin}"
RETRY_DELAY="${RETRY_DELAY:-3}"
# An optional release-please component prefix, then SemVer 2.0 core and
# pre-release (no build metadata: release-please never writes one).
release_re='^([0-9A-Za-z._-]*-)?v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'

fail() {
  echo "::error::$*" >&2
  exit 1
}

case "$CLASSIFY_ONLY" in
  true | false) ;;
  *) fail "CLASSIFY_ONLY must be true or false, not '$CLASSIFY_ONLY'" ;;
esac
[[ "$TAG" =~ $release_re ]] ||
  fail "unusable release tag '$TAG' — expected vMAJOR.MINOR.PATCH, optionally with a -pre-release suffix"
component="${BASH_REMATCH[1]}" # my-lib- of my-lib-v1.2.3, empty for v1.2.3
prerelease=false
[[ -n "${BASH_REMATCH[2]}" ]] && prerelease=true
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "prerelease=${prerelease}" >> "$GITHUB_OUTPUT"
fi
if [[ "$prerelease" == true ]]; then
  echo "ℹ️ ${TAG} is a pre-release: the alias tags stay where they are"
  exit 0
fi
[[ "$CLASSIFY_ONLY" == false ]] || exit 0

: "${GIT_USER_NAME:?GIT_USER_NAME is required}"
: "${GIT_USER_EMAIL:?GIT_USER_EMAIL is required}"

# A component tag gets the same aliases under its own prefix:
# my-lib-v1.2.3 → my-lib-v1, my-lib-v0.3.1 → my-lib-v0 and my-lib-v0.3.
version="${TAG#"$component"}"
major="${component}${version%%.*}" # v1.2.3 → v1
aliases=("$major")
if [[ "${version%%.*}" == v0 ]]; then
  minor="${version#v0.}"
  minor_alias="${component}v0.${minor%%.*}" # v0.24.3 → v0.24
  case "$PRE_MAJOR_ALIAS" in
    both) aliases=("$major" "$minor_alias") ;;
    minor) aliases=("$minor_alias") ;;
    major) aliases=("$major") ;;
    *) fail "unsupported pre-major-alias '$PRE_MAJOR_ALIAS' (expected both, minor or major)" ;;
  esac
fi

if [[ -n "${PUSH_TOKEN:-}" ]]; then
  # Same auth header actions/checkout would have persisted, scoped to this
  # script's git processes through the environment.
  auth="$(printf 'x-access-token:%s' "$PUSH_TOKEN" | base64 | tr -d '\n')"
  echo "::add-mask::${auth}"
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0="http.${GITHUB_SERVER_URL}/.extraheader"
  export GIT_CONFIG_VALUE_0="AUTHORIZATION: basic ${auth}"
fi

git config user.name "$GIT_USER_NAME"
git config user.email "$GIT_USER_EMAIL"

# The release tag straight from the remote: it may not be in a shallow
# checkout.
git fetch --force --no-tags "$REMOTE" "refs/tags/${TAG}:refs/tags/${TAG}" ||
  fail "release tag ${TAG} not found on the remote"
target="$(git rev-parse --verify "refs/tags/${TAG}^{commit}")"

# sync_alias ALIAS: prints the commit the remote's alias points at, if any.
# The local tag goes first: when the fetch fails (no such alias on the remote
# yet, or the remote is unreachable), a tag this script just created would
# otherwise be read back as the remote's, and a rejected push pass for a move.
sync_alias() {
  git tag -d "$1" > /dev/null 2>&1 || true
  git fetch --force --no-tags "$REMOTE" "refs/tags/$1:refs/tags/$1" 2> /dev/null || true
  git rev-parse --verify --quiet "refs/tags/$1^{commit}" || true
}

move_alias() {
  local alias="$1" attempt
  if [[ "$(sync_alias "$alias")" == "$target" ]]; then
    echo "✅ ${alias} already points at ${TAG} (${target}) — nothing to do"
    return 0
  fi
  for attempt in 1 2 3; do
    # Tag the release commit explicitly rather than HEAD: the alias must track
    # the release, not whatever the checkout happens to sit on.
    git tag -fa "$alias" -m "Release $TAG" "$target"
    if git push --force "$REMOTE" "refs/tags/${alias}"; then
      echo "✅ ${alias} → ${TAG} (${target})"
      return 0
    fi
    echo "⚠️  push of ${alias} rejected (attempt ${attempt}/3) — re-syncing"
    if [[ "$(sync_alias "$alias")" == "$target" ]]; then
      echo "✅ ${alias} already points at ${TAG} — moved concurrently"
      return 0
    fi
    sleep "$RETRY_DELAY"
  done
  fail "could not move ${alias} to ${TAG} after 3 attempts"
}

for alias in "${aliases[@]}"; do
  move_alias "$alias"
done
