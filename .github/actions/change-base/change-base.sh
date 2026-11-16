#!/usr/bin/env bash
# Find the change base of a run: the commit its change starts from. A caller
# walks the commits `base..HEAD`, or compares the files of `base` and HEAD.
#
# Lookup, first match wins:
#   override      BASE_REF, when set: a commit, branch or tag. Fails when it is
#                 not in the clone (and cannot be fetched, with FETCH_BASE).
#   pull-request  the pull request's base commit.
#   push          the commit before the push.
#   fork-point    a push whose previous commit is gone (a new branch, or a force
#                 push rewrote it away): the commit where the branch left the
#                 default branch. Never on a push to the default branch itself,
#                 whose own history has no fork point.
#   none          nothing above: a manual or scheduled run, or a clone holding
#                 neither the previous commit nor the default branch. Each
#                 caller decides what that means.
#
# A candidate counts only when it is in the clone. With FETCH_BASE=true and a
# shallow clone, a missing one is fetched first, that one commit at depth 1:
# enough to compare files with HEAD, never to walk the commits in between, as
# `base..HEAD` would stop at the edge of the clone without an error. A complete
# clone fetches nothing: a commit missing there was rewritten away (a force
# push), and the lookup moves on to the fork point. A shallow clone cannot tell
# the two apart, so a force push's discarded tip that origin still serves is
# used. The fork point is never fetched: it needs the history of both branches.
#
# Environment:
#   EVENT           github.event_name
#   REF             github.ref
#   BEFORE          github.event.before
#   PR_BASE         github.event.pull_request.base.sha
#   DEFAULT_BRANCH  github.event.repository.default_branch
#   BASE_REF        optional override
#   FETCH_BASE      true | false (default false)
#   GITHUB_OUTPUT   set by the runner: receives base=<sha or empty>, mode=<mode>
set -euo pipefail

FETCH_BASE="${FETCH_BASE:-false}"
case "$FETCH_BASE" in
  true | false) ;;
  *)
    echo "::error::FETCH_BASE must be true or false, not '$FETCH_BASE'" >&2
    exit 1
    ;;
esac

# A push that creates a branch has an all-zero `before`.
ZERO=0000000000000000000000000000000000000000

# resolve_commit REV: the full SHA of the commit REV names, when it is in the
# clone.
resolve_commit() {
  [[ -n "$1" ]] && git rev-parse --verify --quiet "$1^{commit}" 2> /dev/null
}

# locate REV: resolve_commit REV, fetching it first when FETCH_BASE is on and
# the clone is shallow.
locate() {
  if resolve_commit "$1"; then return 0; fi
  [[ "$FETCH_BASE" == true ]] || return 1
  [[ "$(git rev-parse --is-shallow-repository)" == true ]] || return 1
  if git fetch --quiet --no-tags --depth=1 origin "$1" 2> /dev/null; then
    # FETCH_HEAD is the fetched commit, whether REV was a SHA or a name.
    resolve_commit FETCH_HEAD
  else
    echo "$1 is not in the clone and cannot be fetched from origin." >&2
    return 1
  fi
}

base=""
mode=none
if [[ -n "${BASE_REF:-}" ]]; then
  if ! base="$(locate "$BASE_REF")"; then
    echo "::error::base-ref '$BASE_REF' is not a commit of this clone — on a shallow checkout, use fetch-depth: 0 or set fetch-base." >&2
    exit 1
  fi
  mode=override
else
  candidate=""
  event_mode=""
  case "${EVENT:-}" in
    pull_request | pull_request_target)
      candidate="${PR_BASE:-}"
      event_mode=pull-request
      ;;
    push)
      candidate="${BEFORE:-}"
      event_mode=push
      ;;
  esac
  [[ "$candidate" != "$ZERO" ]] || candidate=""

  if [[ -n "$candidate" ]] && base="$(locate "$candidate")"; then
    mode="$event_mode"
  elif [[ "${EVENT:-}" == push && -n "${DEFAULT_BRANCH:-}" ]] &&
    [[ "${REF:-}" != "refs/heads/${DEFAULT_BRANCH}" ]] &&
    default_tip="$(resolve_commit "refs/remotes/origin/${DEFAULT_BRANCH}")" &&
    base="$(git merge-base "$default_tip" HEAD 2> /dev/null)"; then
    mode=fork-point
  else
    base=""
  fi
fi

echo "Change base: ${base:-none} (${mode})"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "base=$base"
    echo "mode=$mode"
  } >> "$GITHUB_OUTPUT"
fi
