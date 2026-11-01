#!/usr/bin/env bash
# Next pre-release of a branch, v<next>-<type>.<n>, from its Conventional
# Commits since the last final release tag; optionally published as a GitHub
# pre-release.
#
# For a long-lived integration branch (dev) whose final releases ship from
# another branch through release-please. release-please run on that branch
# would track its own pre-release PRs and, after each final release, keep
# counting from its last pre-release (0.23.0-rc.3 once 0.23.0 is out).
# Everything here derives from the last final tag the commit contains, so it
# stays right across releases:
#
#   base  the highest tag vX.Y.Z reachable from SHA. Pre-release tags
#         (v1.2.3-rc.4) and alias tags (v1, v1.2) are ignored. None: 0.0.0.
#   next  base bumped the way release-please bumps it: a breaking change
#         bumps major, a feat minor, a fix, perf or revert patch, with
#         bump-minor-pre-major and bump-patch-for-minor-pre-major read from
#         the release-please config. Other types release nothing.
#   n     the number of commits from base to SHA. It is unique per commit of
#         the branch, so it is known before the build that bakes it in, and
#         two runs never compete for the same number.
#
# Modes:
#   plan     compute only.
#   publish  also create the tag on SHA and its GitHub pre-release, never
#            marked latest. A re-run finds the release already there and does
#            nothing; a tag of the same name on another commit is an error.
#
# Outputs (GITHUB_OUTPUT, and stdout): releasable, tag, version, base-tag.
# The release notes go to NOTES_FILE, grouped like release-please's changelog.
# Talks to the REST API with curl, the token in a header file, never on a
# command line: self-hosted runner images often ship no GitHub CLI.
#
# Env: MODE             plan | publish (default plan)
#      SHA              commit to pre-release (default HEAD)
#      PRERELEASE_TYPE  pre-release identifier (default rc)
#      CONFIG_FILE      release-please config holding the bump rules. Empty:
#                       .github/release/release-please-config.json, then
#                       release-please-config.json, else both rules off
#      TAG              publish: the tag an earlier plan computed, checked
#                       against this run's (default: no check)
#      NOTES_FILE       release notes (default $RUNNER_TEMP/prerelease-notes.md)
#      GITHUB_TOKEN     publish: contents write
#      GITHUB_REPOSITORY, GITHUB_API_URL, GITHUB_SERVER_URL
#                       publish, and the commit links of the notes
set -euo pipefail

MODE="${MODE:-plan}"
PRERELEASE_TYPE="${PRERELEASE_TYPE:-rc}"
CONFIG_FILE="${CONFIG_FILE:-}"
TAG="${TAG:-}"
NOTES_FILE="${NOTES_FILE:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/prerelease-notes.md}"

fail() {
  echo "::error::$*" >&2
  exit 1
}

case "$MODE" in
  plan | publish) ;;
  *) fail "MODE must be plan or publish, not '$MODE'" ;;
esac
# A SemVer pre-release identifier: letters, digits and hyphens, not digits only.
if [[ ! "$PRERELEASE_TYPE" =~ ^[0-9A-Za-z-]+$ || "$PRERELEASE_TYPE" =~ ^[0-9]+$ ]]; then
  fail "PRERELEASE_TYPE must be letters, digits and hyphens, not digits only: '$PRERELEASE_TYPE'"
fi

requested="${SHA:-HEAD}"
SHA="$(git rev-parse --verify --quiet "${requested}^{commit}")" ||
  fail "not a commit of this checkout: '$requested' (a pre-release needs the full history)"

if [[ -z "$CONFIG_FILE" ]]; then
  for candidate in .github/release/release-please-config.json release-please-config.json; do
    if [[ -f "$candidate" ]]; then
      CONFIG_FILE="$candidate"
      break
    fi
  done
elif [[ ! -f "$CONFIG_FILE" ]]; then
  fail "CONFIG_FILE not found: '$CONFIG_FILE'"
fi

# rule KEY: the release-please setting KEY, true or false. The package "."
# setting wins over the top-level one; absent, false, release-please's default.
rule() {
  if [[ -z "$CONFIG_FILE" ]]; then
    echo false
    return
  fi
  jq -r --arg k "$1" '
    ((.packages // {})["."] // {}) as $pkg
    | if ($pkg | has($k)) then $pkg[$k] elif has($k) then .[$k] else false end
    | if . == true then "true" else "false" end' "$CONFIG_FILE"
}
minor_pre_major="$(rule bump-minor-pre-major)"
patch_for_minor_pre_major="$(rule bump-patch-for-minor-pre-major)"

# The last final release: the highest vX.Y.Z tag the commit contains.
base_tag="$(git tag --merged "$SHA" --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 || true)"
if [[ -n "$base_tag" ]]; then
  base="${base_tag#v}"
  range="${base_tag}..${SHA}"
else
  base=0.0.0
  range="$SHA"
fi
IFS=. read -r major minor patch <<< "$base"
count="$(git rev-list --count "$range")"

repo_url=""
if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
  repo_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}"
fi

# Conventional Commits since the base: the strongest bump, and the notes.
bump=0 # 3 major, 2 minor, 1 patch, 0 nothing to release
breaking=() features=() fixes=() perfs=() reverts=()
header_re='^([A-Za-z]+)(\(([^)]*)\))?(!)?: (.+)$'
while IFS=$'\x1f' read -r -d $'\x1e' hash subject body; do
  hash="${hash#$'\n'}"
  [[ "$subject" =~ $header_re ]] || continue
  type="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
  scope="${BASH_REMATCH[3]}"
  bang="${BASH_REMATCH[4]}"
  description="${BASH_REMATCH[5]}"
  if [[ -n "$repo_url" ]]; then
    ref="[${hash:0:7}](${repo_url}/commit/${hash})"
  else
    ref="${hash:0:7}"
  fi
  entry="* ${scope:+**${scope}:** }${description} (${ref})"
  level=0
  case "$type" in
    feat)
      level=2
      features+=("$entry")
      ;;
    fix)
      level=1
      fixes+=("$entry")
      ;;
    perf)
      level=1
      perfs+=("$entry")
      ;;
    revert)
      level=1
      reverts+=("$entry")
      ;;
  esac
  if [[ -n "$bang" ]] || grep -qE '^BREAKING[ -]CHANGE: ' <<< "$body"; then
    level=3
    breaking+=("$entry")
  fi
  if ((level > bump)); then
    bump=$level
  fi
done < <(git log --format='%H%x1f%s%x1f%b%x1e' "$range")

releasable=false tag="" version=""
if ((bump > 0)); then
  case "$bump" in
    3)
      if ((major == 0)) && [[ "$minor_pre_major" == true ]]; then
        minor=$((minor + 1)) patch=0
      else
        major=$((major + 1)) minor=0 patch=0
      fi
      ;;
    2)
      if ((major == 0)) && [[ "$patch_for_minor_pre_major" == true ]]; then
        patch=$((patch + 1))
      else
        minor=$((minor + 1)) patch=0
      fi
      ;;
    1) patch=$((patch + 1)) ;;
  esac
  releasable=true
  version="${major}.${minor}.${patch}-${PRERELEASE_TYPE}.${count}"
  tag="v${version}"
fi

# section TITLE ENTRY...: one notes section, nothing when there is no entry.
section() {
  local title="$1"
  shift
  (($# > 0)) || return 0
  printf '\n### %s\n\n' "$title"
  printf '%s\n' "$@"
}
mkdir -p "$(dirname "$NOTES_FILE")"
if [[ "$releasable" == true ]]; then
  {
    printf 'Pre-release of %s toward v%s.%s.%s: %s commit(s) since %s.\n' \
      "${SHA:0:7}" "$major" "$minor" "$patch" "$count" "${base_tag:-the first commit}"
    section "⚠ BREAKING CHANGES" ${breaking[@]+"${breaking[@]}"}
    section "Features" ${features[@]+"${features[@]}"}
    section "Bug Fixes" ${fixes[@]+"${fixes[@]}"}
    section "Performance Improvements" ${perfs[@]+"${perfs[@]}"}
    section "Reverts" ${reverts[@]+"${reverts[@]}"}
  } > "$NOTES_FILE"
else
  : > "$NOTES_FILE"
fi

output() {
  printf '%s=%s\n' "$1" "$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
  fi
}
output releasable "$releasable"
output tag "$tag"
output version "$version"
output base-tag "$base_tag"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  if [[ "$releasable" == true ]]; then
    printf "### Pre-release \`%s\`\n\n" "$tag"
    cat "$NOTES_FILE"
  else
    printf 'Nothing to pre-release: no feat, fix, perf, revert or breaking change since %s.\n' \
      "${base_tag:-the first commit}"
  fi >> "$GITHUB_STEP_SUMMARY"
fi

[[ "$MODE" == publish ]] || exit 0

if [[ -n "$TAG" && "$TAG" != "$tag" ]]; then
  fail "TAG '$TAG' is not the pre-release of ${SHA:0:7}, which is '${tag:-none}'"
fi
if [[ "$releasable" != true ]]; then
  echo "Nothing to publish: no feat, fix, perf, revert or breaking change since ${base_tag:-the first commit}."
  exit 0
fi
: "${GITHUB_TOKEN:?GITHUB_TOKEN is required to publish}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required to publish}"

work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/prerelease.XXXXXX")"
trap 'rm -rf "$work"' EXIT
(umask 077 && printf 'Authorization: Bearer %s\n' "$GITHUB_TOKEN" > "$work/auth-header")
api_root="${GITHUB_API_URL:-https://api.github.com}/repos/${GITHUB_REPOSITORY}"

# api RESPONSE [curl args...]: prints the HTTP status; the body, error answers
# included, lands in RESPONSE.
api() {
  local response="$1"
  shift
  curl -sS --retry 3 --retry-delay 2 \
    -H @"$work/auth-header" \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    -o "$response" -w '%{http_code}' "$@"
}
message() { jq -r '.message? // empty' "$1" 2> /dev/null || true; }

# A tag of that name on another commit means the branch was rewritten: stop
# rather than move a published version.
status="$(api "$work/commit.json" "$api_root/commits/$tag")"
case "$status" in
  200)
    existing="$(jq -r '.sha' "$work/commit.json")"
    [[ "$existing" == "$SHA" ]] || fail "tag $tag already exists on ${existing:0:7}, not on ${SHA:0:7}"
    ;;
  404 | 422) ;;
  *) fail "GitHub answered $status looking up $tag: $(message "$work/commit.json")" ;;
esac

status="$(api "$work/release.json" "$api_root/releases/tags/$tag")"
case "$status" in
  200)
    echo "Pre-release $tag is already published: $(jq -r '.html_url' "$work/release.json")"
    exit 0
    ;;
  404) ;;
  *) fail "GitHub answered $status looking up the release $tag: $(message "$work/release.json")" ;;
esac

jq -n --arg tag "$tag" --arg sha "$SHA" --rawfile body "$NOTES_FILE" \
  '{tag_name: $tag, target_commitish: $sha, name: $tag, body: $body, prerelease: true, make_latest: "false"}' \
  > "$work/payload.json"
status="$(api "$work/created.json" -X POST -H 'Content-Type: application/json' \
  --data-binary @"$work/payload.json" "$api_root/releases")"
[[ "$status" == 201 ]] || fail "GitHub answered $status creating the pre-release $tag: $(message "$work/created.json")"
echo "Published pre-release $tag: $(jq -r '.html_url' "$work/created.json")"
