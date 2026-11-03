#!/usr/bin/env bash
# Open a pull request in each consumer repository that moves its pins of
# SOURCE's workflows and actions to a release (the rules are at the top of
# bump-pins.py), and turn on auto-merge so it lands once its checks pass.
#
# For each entry of REPOSITORIES, `name` or `name:branch` (a repository of
# SOURCE's owner; the branch defaults to the repository's default branch):
#   1. read the .yml and .yaml files under .github/ on the branch;
#   2. move the pins; nothing to move: on to the next repository;
#   3. commit the changes through the API, so GitHub signs the commit, on the
#      branch bump/<source name>, based on the branch's tip. Every release
#      force-updates that branch: one pull request follows the latest release;
#   4. open the pull request, or update the one already open;
#   5. turn on auto-merge, with the first merge method the repository and
#      the branch's rules allow (squash, merge, rebase). Without auto-merge
#      allowed on the repository, or when the pull request could merge at
#      once (no required check), it stays open for a person, with a notice:
#      nothing merges before CI has run.
# An archived repository is skipped. A repository that fails is reported, the
# next one still runs, and the run fails at the end.
#
# Talks to the REST and GraphQL APIs with curl, each token in a header file,
# never on a command line: self-hosted runner images often ship no GitHub CLI.
#
# Env: REPOSITORIES  consumer repositories, one per line or comma-separated
#                    (required)
#      TAG           release to move to, vX.Y.Z; empty: SOURCE's latest release
#      AUTO_MERGE    true: turn on auto-merge (default true)
#      DRY_RUN       true: print what would move, write nothing (default false)
#      GITHUB_TOKEN  contents, pull-requests and workflows write on the
#                    consumers: a GitHub App installation token (required)
#      SOURCE_TOKEN  reads SOURCE's releases (default: GITHUB_TOKEN)
#      SOURCE        owner/name whose pins move (default: GITHUB_REPOSITORY)
#      GITHUB_API_URL, GITHUB_GRAPHQL_URL, GITHUB_SERVER_URL  set by the runner
set -euo pipefail

AUTO_MERGE="${AUTO_MERGE:-true}"
DRY_RUN="${DRY_RUN:-false}"
TAG="${TAG:-}"
SOURCE="${SOURCE:-${GITHUB_REPOSITORY:-}}"
release_re='^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'

fail() {
  echo "::error::$*" >&2
  exit 1
}

for name in AUTO_MERGE DRY_RUN; do
  case "${!name}" in
    true | false) ;;
    *) fail "$name must be true or false, not '${!name}'" ;;
  esac
done
: "${REPOSITORIES:?REPOSITORIES is required}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
SOURCE_TOKEN="${SOURCE_TOKEN:-$GITHUB_TOKEN}"
[[ "$SOURCE" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "SOURCE must be owner/name, not '$SOURCE'"
[[ -z "$TAG" || "$TAG" =~ $release_re ]] || fail "TAG must be a release vX.Y.Z, not '$TAG'"
# The tokens travel only over TLS, to the API roots the runner names.
api_url="${GITHUB_API_URL:-https://api.github.com}"
api_url="${api_url%/}"
graphql_url="${GITHUB_GRAPHQL_URL:-${api_url}/graphql}"
server_url="${GITHUB_SERVER_URL:-https://github.com}"
for url in "$api_url" "$graphql_url"; do
  case "$url" in
    https://[!/]*) ;;
    *) fail "the API URLs must be https:// URLs, not '$url'" ;;
  esac
done
owner="${SOURCE%%/*}"
branch="bump/${SOURCE#*/}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/propagate-release.XXXXXX")"
trap 'rm -rf "$work"' EXIT
(
  umask 077
  printf 'Authorization: Bearer %s\n' "$GITHUB_TOKEN" > "$work/auth-header"
  printf 'Authorization: Bearer %s\n' "$SOURCE_TOKEN" > "$work/source-auth-header"
)

# The entries, name or name:branch, trimmed and each once, before any request.
printf '%s\n' "$REPOSITORIES" | tr ',' '\n' |
  awk '{ gsub(/^[ \t\r]+|[ \t\r]+$/, "") } $0 != "" && !seen[$0]++' > "$work/entries"
while IFS= read -r entry; do
  [[ "$entry" =~ ^[A-Za-z0-9_.-]+(:[A-Za-z0-9._/-]+)?$ ]] ||
    fail "REPOSITORIES: '$entry' is not a repository name, optionally followed by :branch"
done < "$work/entries"
[[ -s "$work/entries" ]] || fail "REPOSITORIES lists no repository"

# api RESPONSE AUTH [curl args...]: prints the HTTP status; the body, error
# answers included, lands in RESPONSE. AUTH names the header file to send; the
# caller may set `accept` for another media type.
api() {
  local response="$1" auth="$2"
  shift 2
  curl -sS --retry 3 --retry-delay 2 --max-time 60 \
    -H @"$work/$auth" \
    -H "Accept: ${accept:-application/vnd.github+json}" \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    -o "$response" -w '%{http_code}' "$@"
}
# GitHub's message, flattened and stripped of '::' so it cannot inject a
# workflow command.
message() {
  local text
  text="$(jq -r '.message? // (.errors? // [] | map(.message) | join("; ")) // empty' "$1" 2> /dev/null || true)"
  text="${text//$'\n'/ }"
  printf '%s' "${text//::/: :}"
}
# post RESPONSE PATH_OR_URL PAYLOAD [METHOD]: sends PAYLOAD as JSON, prints the
# HTTP status.
post() {
  api "$1" auth-header -X "${4:-POST}" -H 'Content-Type: application/json' --data-binary @"$3" "$2"
}

# The release and its commit.
source_root="${api_url}/repos/${SOURCE}"
if [[ -z "$TAG" ]]; then
  status="$(api "$work/latest.json" source-auth-header "$source_root/releases/latest")"
  [[ "$status" == 200 ]] || fail "GitHub answered $status reading the latest release of $SOURCE: $(message "$work/latest.json")"
  TAG="$(jq -r '.tag_name // empty' "$work/latest.json")"
  [[ "$TAG" =~ $release_re ]] || fail "the latest release of $SOURCE is not a vX.Y.Z tag: '$TAG'"
fi
status="$(api "$work/commit.json" source-auth-header "$source_root/commits/$TAG")"
[[ "$status" == 200 ]] || fail "GitHub answered $status reading $TAG of $SOURCE: $(message "$work/commit.json")"
sha="$(jq -r '.sha // empty' "$work/commit.json")"
[[ "$sha" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] || fail "unexpected commit for $TAG: '$sha'"
title="ci(deps): bump ${SOURCE} to ${TAG}"
echo "Moving the pins of ${SOURCE} to ${TAG} (${sha:0:7})."
if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run: nothing is written."
fi

: > "$work/results.tsv"
# result OUTCOME [URL]: one line of the summary for the current repository.
result() {
  printf '%s\t%s\t%s\n' "$repo" "$1" "${2:-}" >> "$work/results.tsv"
  echo "${repo}: $1${2:+ $2}"
}
# problem MESSAGE: the current repository failed; the run goes on.
problem() {
  echo "::error::${repo}: $*"
  result "failed: $*"
  return 1
}

# propagate NAME BASE: the pull request of one repository.
propagate() {
  local name="$1" base="$2" status root dir path mode blob base_sha base_tree new_tree commit existing number url node method reason
  repo="${owner}/${name}"
  root="${api_url}/repos/${repo}"
  dir="$work/repos/$name"
  mkdir -p "$dir/files"

  status="$(api "$dir/repo.json" auth-header "$root")"
  case "$status" in
    200) ;;
    403 | 404) problem "not reachable (GitHub answered $status): install the GitHub App on it" || return ;;
    *) problem "GitHub answered $status reading the repository: $(message "$dir/repo.json")" || return ;;
  esac
  if [[ "$(jq -r '.archived' "$dir/repo.json")" == true ]]; then
    result "skipped: archived"
    return 0
  fi
  [[ -n "$base" ]] || base="$(jq -r '.default_branch // empty' "$dir/repo.json")"
  [[ "$base" =~ ^[A-Za-z0-9._/-]+$ ]] || problem "unexpected branch name '$base'" || return

  status="$(api "$dir/base.json" auth-header "$root/git/ref/heads/$base")"
  [[ "$status" == 200 ]] || problem "GitHub answered $status reading the branch $base: $(message "$dir/base.json")" || return
  base_sha="$(jq -r '.object.sha' "$dir/base.json")"
  status="$(api "$dir/tree.json" auth-header "$root/git/trees/$base_sha?recursive=1")"
  [[ "$status" == 200 ]] || problem "GitHub answered $status reading the files of $base: $(message "$dir/tree.json")" || return
  if jq -e '.truncated == true' "$dir/tree.json" > /dev/null; then
    problem "too many files to list in one request" || return
  fi
  base_tree="$(jq -r '.sha' "$dir/tree.json")"
  # Workflows and composite actions: the .yml and .yaml files under .github/.
  jq -r '.tree[] | select(.type == "blob" and (.path | test("^\\.github/[A-Za-z0-9._/-]+\\.ya?ml$"))
    and (.path | split("/") | index("..") | not)) | [.path, .mode, .sha] | @tsv' "$dir/tree.json" > "$dir/files.tsv"

  : > "$dir/paths"
  while IFS=$'\t' read -r path mode blob; do
    [[ "$blob" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] || problem "unexpected blob for $path" || return
    mkdir -p "$(dirname "$dir/files/$path")"
    status="$(accept=application/vnd.github.raw api "$dir/files/$path" auth-header "$root/git/blobs/$blob")"
    [[ "$status" == 200 ]] || problem "GitHub answered $status reading $path" || return
    printf '%s\n' "$dir/files/$path" >> "$dir/paths"
  done < "$dir/files.tsv"
  : > "$dir/moves.tsv"
  if [[ -s "$dir/paths" ]]; then
    local -a paths
    mapfile -t paths < "$dir/paths"
    python3 "$here/bump-pins.py" "$SOURCE" "$TAG" "$sha" "${paths[@]}" > "$dir/moves.raw"
    while IFS=$'\t' read -r path ref old new; do
      printf '%s\t%s\t%s\t%s\n' "${path#"$dir/files/"}" "$ref" "$old" "$new"
    done < "$dir/moves.raw" > "$dir/moves.tsv"
  fi
  if [[ ! -s "$dir/moves.tsv" ]]; then
    result "nothing to move"
    return 0
  fi
  while IFS=$'\t' read -r path ref old new; do
    echo "  ${path}: ${ref} ${old} -> ${new}"
  done < "$dir/moves.tsv"
  cut -f1 "$dir/moves.tsv" | awk '!seen[$0]++' > "$dir/changed"
  if [[ "$DRY_RUN" == true ]]; then
    result "would move $(wc -l < "$dir/moves.tsv" | tr -d ' ') pin(s) in $(wc -l < "$dir/changed" | tr -d ' ') file(s)"
    return 0
  fi

  # One blob per changed file, one tree on top of the branch's.
  echo '[]' > "$dir/entries.json"
  while IFS= read -r path; do
    mode="$(awk -F'\t' -v p="$path" '$1 == p { print $2; exit }' "$dir/files.tsv")"
    base64 < "$dir/files/$path" | tr -d '\n' > "$dir/content.b64"
    jq -n --rawfile content "$dir/content.b64" '{content: $content, encoding: "base64"}' > "$dir/blob-request.json"
    status="$(post "$dir/blob.json" "$root/git/blobs" "$dir/blob-request.json")"
    [[ "$status" == 201 ]] || problem "GitHub answered $status storing $path: $(message "$dir/blob.json")" || return
    jq --arg path "$path" --arg mode "$mode" --arg sha "$(jq -r '.sha' "$dir/blob.json")" \
      '. + [{path: $path, mode: $mode, type: "blob", sha: $sha}]' "$dir/entries.json" > "$dir/entries.next"
    mv "$dir/entries.next" "$dir/entries.json"
  done < "$dir/changed"
  jq -n --arg base "$base_tree" --slurpfile entries "$dir/entries.json" '{base_tree: $base, tree: $entries[0]}' \
    > "$dir/tree-request.json"
  status="$(post "$dir/new-tree.json" "$root/git/trees" "$dir/tree-request.json")"
  [[ "$status" == 201 ]] || problem "GitHub answered $status storing the tree: $(message "$dir/new-tree.json")" || return
  new_tree="$(jq -r '.sha' "$dir/new-tree.json")"

  # The branch already holds this tree on this base: nothing to push again.
  existing=""
  status="$(api "$dir/head.json" auth-header "$root/git/ref/heads/$branch")"
  case "$status" in
    200) existing="$(jq -r '.object.sha' "$dir/head.json")" ;;
    404) ;;
    *) problem "GitHub answered $status reading the branch $branch: $(message "$dir/head.json")" || return ;;
  esac
  commit=""
  if [[ -n "$existing" ]]; then
    status="$(api "$dir/existing.json" auth-header "$root/git/commits/$existing")"
    if [[ "$status" == 200 ]] &&
      jq -e --arg tree "$new_tree" --arg parent "$base_sha" \
        '.tree.sha == $tree and (.parents | length) == 1 and .parents[0].sha == $parent' "$dir/existing.json" > /dev/null; then
      commit="$existing"
    fi
  fi
  if [[ -z "$commit" ]]; then
    jq -n --arg message "$title" --arg tree "$new_tree" --arg parent "$base_sha" \
      --arg notes "Moves the pins of ${SOURCE} to ${TAG}: ${server_url}/${SOURCE}/releases/tag/${TAG}" \
      '{message: ($message + "\n\n" + $notes), tree: $tree, parents: [$parent]}' > "$dir/commit-request.json"
    status="$(post "$dir/commit.json" "$root/git/commits" "$dir/commit-request.json")"
    [[ "$status" == 201 ]] || problem "GitHub answered $status creating the commit: $(message "$dir/commit.json")" || return
    commit="$(jq -r '.sha' "$dir/commit.json")"
    if [[ -n "$existing" ]]; then
      jq -n --arg sha "$commit" '{sha: $sha, force: true}' > "$dir/ref-request.json"
      status="$(post "$dir/ref.json" "$root/git/refs/heads/$branch" "$dir/ref-request.json" PATCH)"
      [[ "$status" == 200 ]] || problem "GitHub answered $status updating $branch: $(message "$dir/ref.json")" || return
    else
      jq -n --arg ref "refs/heads/$branch" --arg sha "$commit" '{ref: $ref, sha: $sha}' > "$dir/ref-request.json"
      status="$(post "$dir/ref.json" "$root/git/refs" "$dir/ref-request.json")"
      [[ "$status" == 201 ]] || problem "GitHub answered $status creating $branch: $(message "$dir/ref.json")" || return
    fi
  fi

  # The pull request: opened once, then kept up to date.
  {
    printf "Moves the pins of [%s](%s/%s) to [%s](%s/%s/releases/tag/%s) (\`%s\`).\n\n" \
      "$SOURCE" "$server_url" "$SOURCE" "$TAG" "$server_url" "$SOURCE" "$TAG" "${sha:0:7}"
    printf '| File | Reference | From | To |\n| ---- | --------- | ---- | -- |\n'
    while IFS=$'\t' read -r path ref old new; do
      printf "| \`%s\` | \`%s\` | %s | %s |\n" "$path" "$ref" "$old" "$new"
    done < "$dir/moves.tsv"
    printf '\nOpened by the release of %s. The next release updates this pull request: a commit pushed to its branch is overwritten then.\n' "$SOURCE"
  } > "$dir/body.md"
  status="$(api "$dir/pulls.json" auth-header "$root/pulls?state=open&head=${owner}:${branch}&base=${base}")"
  [[ "$status" == 200 ]] || problem "GitHub answered $status listing the pull requests: $(message "$dir/pulls.json")" || return
  number="$(jq -r '.[0].number // empty' "$dir/pulls.json")"
  if [[ -n "$number" ]]; then
    jq -n --arg title "$title" --rawfile body "$dir/body.md" '{title: $title, body: $body}' > "$dir/pull-request.json"
    status="$(post "$dir/pull.json" "$root/pulls/$number" "$dir/pull-request.json" PATCH)"
    [[ "$status" == 200 ]] || problem "GitHub answered $status updating pull request #$number: $(message "$dir/pull.json")" || return
  else
    jq -n --arg title "$title" --arg head "$branch" --arg base "$base" --rawfile body "$dir/body.md" \
      '{title: $title, head: $head, base: $base, body: $body}' > "$dir/pull-request.json"
    status="$(post "$dir/pull.json" "$root/pulls" "$dir/pull-request.json")"
    [[ "$status" == 201 ]] || problem "GitHub answered $status opening the pull request: $(message "$dir/pull.json")" || return
  fi
  url="$(jq -r '.html_url' "$dir/pull.json")"
  node="$(jq -r '.node_id' "$dir/pull.json")"

  if [[ "$AUTO_MERGE" != true ]]; then
    result "pull request" "$url"
    return 0
  fi
  if jq -e '.auto_merge != null' "$dir/pull.json" > /dev/null; then
    result "pull request, merges once its checks pass" "$url"
    return 0
  fi
  # The first merge method that both the repository and the rules of the
  # target branch allow: a ruleset can narrow them, to rebase only for
  # instance. A private repository on GitHub Free has no rules (GitHub
  # answers 403): its settings decide alone.
  status="$(api "$dir/rules.json" auth-header "$root/rules/branches/$base")"
  [[ "$status" == 200 ]] || echo '[]' > "$dir/rules.json"
  method="$(jq -rn --slurpfile repo "$dir/repo.json" --slurpfile rules "$dir/rules.json" '
    $repo[0] as $settings
    | [$rules[0][]? | select(.type == "pull_request") | .parameters.allowed_merge_methods // empty] as $lists
    | [{name: "squash", on: $settings.allow_squash_merge}, {name: "merge", on: $settings.allow_merge_commit},
       {name: "rebase", on: $settings.allow_rebase_merge}]
    | map(select(.on != false and (.name as $m | all($lists[]; any(.[]; . == $m)))))
    | (.[0].name // "squash") | ascii_upcase')"
  jq -n --arg id "$node" --arg method "$method" '{
    query: "mutation($id: ID!, $method: PullRequestMergeMethod!) { enablePullRequestAutoMerge(input: {pullRequestId: $id, mergeMethod: $method}) { clientMutationId } }",
    variables: {id: $id, method: $method}}' > "$dir/automerge-request.json"
  status="$(post "$dir/automerge.json" "$graphql_url" "$dir/automerge-request.json")"
  if [[ "$status" == 200 ]] && jq -e '(.errors // []) | length == 0' "$dir/automerge.json" > /dev/null; then
    result "pull request, merges once its checks pass" "$url"
    return 0
  fi
  reason="$(message "$dir/automerge.json")"
  case "$reason" in
    # How the repository is set up, not a failure: auto-merge is off in its
    # settings (always, for a private repository on GitHub Free), or its
    # branch requires no status check for auto-merge to wait for.
    *"Auto merge is not allowed"* | *"clean status"*)
      echo "::notice::${repo}: no auto-merge (${reason}): the pull request waits for a person."
      ;;
    *) echo "::warning::${repo}: auto-merge not turned on (${reason}): the pull request waits for a person." ;;
  esac
  result "pull request, to merge by hand" "$url"
}

failed=0
while IFS= read -r entry; do
  name="${entry%%:*}"
  base=""
  [[ "$entry" != *:* ]] || base="${entry#*:}"
  if [[ "${owner}/${name}" == "$SOURCE" ]]; then
    echo "${SOURCE}: skipped, it is the source"
    continue
  fi
  # A subshell with errexit on: called from a condition, a function would run
  # with errexit off, and an unexpected failure would go unnoticed.
  set +e
  (
    set -e
    propagate "$name" "$base"
  )
  status=$?
  set -e
  if ((status != 0)); then
    failed=$((failed + 1))
    if ! awk -F'\t' -v r="${owner}/${name}" '$1 == r { found = 1 } END { exit !found }' "$work/results.tsv"; then
      repo="${owner}/${name}"
      echo "::error::${repo}: failed (exit status ${status}): see the log above"
      result "failed: unexpected error, see the log"
    fi
  fi
done < "$work/entries"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  mode=""
  if [[ "$DRY_RUN" == true ]]; then
    mode=" (dry run)"
  fi
  {
    printf '### Propagate %s %s%s\n\n' "$SOURCE" "$TAG" "$mode"
    printf '| Repository | Result |\n| ---------- | ------ |\n'
    while IFS=$'\t' read -r repository outcome url; do
      printf "| \`%s\` | %s%s |\n" "$repository" "$outcome" "${url:+ — $url}"
    done < "$work/results.tsv"
  } >> "$GITHUB_STEP_SUMMARY"
fi
if ((failed > 0)); then
  fail "${failed} repository(ies) failed: see the errors above"
fi
