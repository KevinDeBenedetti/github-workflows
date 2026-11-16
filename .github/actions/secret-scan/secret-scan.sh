#!/usr/bin/env bash
# Scan the commits a run brings for leaked secrets with gitleaks, using the
# configuration of a trusted commit, never of the commits under scan.
#
# Range: `BASE..HEAD` from the change base (the change-base action: the pull
# request's base, the commit before the push, or the fork point of a new or
# force-pushed branch; the default branch's own pushes scan the rest). Without
# a change base, all fetched history. No --first-parent anywhere: on a pull
# request HEAD is the synthetic merge commit whose first parent is the base
# branch, and on a push to the default branch after a merge commit the feature
# commits only sit behind the second parent. Following first parents would skip
# exactly the commits that need scanning.
#
# Trusted commit: where .gitleaks.toml and .gitleaksignore are read from.
# Gitleaks otherwise auto-loads both from the checkout, so a change could add
# an allowlist matching everything and silence its own leaks.
#   change base set         the change base
#   manual run              the default branch (reviewed; this run cannot
#                           change it), when it is in the clone
#   scheduled run           HEAD, the default branch's own tip
#   otherwise               none: gitleaks' default rules and an empty ignore
#                           list, with a warning (fail closed)
# A trusted config that `[extend]`s a `path` gets that file restored from the
# trusted commit too; a path outside the repository fails. With a range, the
# scan warns when the range changes the config or adds `gitleaks:allow`
# comments: both silence findings once merged.
#
# Environment:
#   BASE                 the change base (full SHA), empty when there is none
#   EVENT                github.event_name
#   BEFORE               github.event.before (for the push warning)
#   DEFAULT_BRANCH       github.event.repository.default_branch
#   IGNORE_INLINE_ALLOW  true: disregard inline `gitleaks:allow` comments
#   REPORT_PATH          SARIF report to write (default results.sarif)
#   RUNNER_TEMP          set by the runner
# Exits with gitleaks' status: 1 when a leak is found.
set -euo pipefail

BASE="${BASE:-}"
EVENT="${EVENT:-}"
BEFORE="${BEFORE:-}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-}"
IGNORE_INLINE_ALLOW="${IGNORE_INLINE_ALLOW:-false}"
REPORT_PATH="${REPORT_PATH:-results.sarif}"

fail() {
  echo "::error::$*" >&2
  exit 1
}

case "$IGNORE_INLINE_ALLOW" in
  true | false) ;;
  *) fail "IGNORE_INLINE_ALLOW must be true or false, not '$IGNORE_INLINE_ALLOW'" ;;
esac

has_commit() { [[ -n "$1" ]] && git cat-file -e "$1^{commit}" 2> /dev/null; }

range=""
trusted=""
if [[ -n "$BASE" ]]; then
  has_commit "$BASE" || fail "Change base $BASE is not in the clone."
  range="${BASE}..HEAD"
  trusted="$BASE"
elif [[ "$EVENT" == workflow_dispatch && -n "$DEFAULT_BRANCH" ]] &&
  has_commit "refs/remotes/origin/${DEFAULT_BRANCH}"; then
  trusted="refs/remotes/origin/${DEFAULT_BRANCH}"
elif [[ "$EVENT" == schedule ]]; then
  trusted=HEAD
else
  # No trusted commit: the change base fell outside a shallow clone (which
  # lacks the default branch), or the default branch itself was force-pushed
  # or pushed for the first time.
  consequence="All fetched history is scanned with gitleaks' default rules, without the repository's ignore list — findings already triaged there are reported again."
  case "$EVENT" in
    workflow_dispatch)
      echo "::warning::The default branch (${DEFAULT_BRANCH:-unknown}) is not in this clone: a finite fetch depth fetches the triggering branch only. Gitleaks' default rules apply, without the repository's ignore list."
      ;;
    push)
      echo "::warning::No trusted commit to start the scan from: the commit before this push (${BEFORE:0:7}) is not in this clone, and the default branch cannot stand in for it. $consequence"
      ;;
    pull_request*)
      echo "::warning::No trusted commit to start the scan from: the pull request's base commit is not in this clone (a finite fetch depth). $consequence"
      ;;
    *)
      echo "::warning::No trusted commit to start the scan from on a ${EVENT:-unknown} event. $consequence"
      ;;
  esac
fi

# Fail closed: without a trusted copy, gitleaks' default rules (an explicit
# --config also stops the auto-load from the checkout) and an empty ignore list.
config_dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/gitleaks-config.XXXXXX")"
trap 'rm -rf "$config_dir"' EXIT
default_config() { printf '[extend]\nuseDefault = true\n'; }
default_config > "$config_dir/gitleaks.toml"
: > "$config_dir/.gitleaksignore"

watched=(.gitleaks.toml .gitleaksignore)
if [[ -n "$trusted" ]]; then
  git show "${trusted}:.gitleaks.toml" > "$config_dir/gitleaks.toml" 2> /dev/null ||
    default_config > "$config_dir/gitleaks.toml"
  git show "${trusted}:.gitleaksignore" > "$config_dir/.gitleaksignore" 2> /dev/null ||
    : > "$config_dir/.gitleaksignore"

  # `[extend] path = "..."` is resolved against the working directory, i.e.
  # the checkout under scan: restore that file from the trusted commit too, or
  # the change could rewrite the extended config.
  extend_path="$(awk '
    /^[[:space:]]*\[/ { in_extend = ($0 ~ /^[[:space:]]*\[extend\]/) ; next }
    in_extend && /^[[:space:]]*path[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*["\047]/, ""); sub(/["\047].*$/, ""); print; exit
    }' "$config_dir/gitleaks.toml")"
  if [[ -n "$extend_path" ]]; then
    extend_rel="${extend_path#./}"
    case "$extend_rel" in
      /* | *..*) fail ".gitleaks.toml extends '${extend_path}' outside the repository — not supported" ;;
    esac
    mkdir -p "$(dirname "$extend_rel")"
    git show "${trusted}:${extend_rel}" > "$extend_rel" 2> /dev/null ||
      fail "extended config '${extend_rel}' not found at ${trusted:0:7}"
    watched+=("$extend_rel")
  fi

  # Only with a range: a manual or scheduled run has nothing to compare.
  if [[ -n "$range" ]]; then
    # Config changes in the scanned range take effect once merged: flag them
    # so the reviewer looks at what they would silence.
    changed="$(git diff --name-only "$range" -- "${watched[@]}" 2> /dev/null || true)"
    if [[ -n "$changed" ]]; then
      echo "::warning::This change modifies $(echo "$changed" | tr '\n' ' ')— not applied to this scan (the config of ${trusted:0:7} is used). Review what it allowlists before merging."
    fi
    # Inline `gitleaks:allow` comments silence the finding on their line.
    allows="$(git diff --unified=0 "$range" 2> /dev/null | grep -c '^+.*gitleaks:allow' || true)"
    if ((${allows:-0} > 0)); then
      echo "::warning::This change adds ${allows} \`gitleaks:allow\` comment(s), each silencing a finding — check them before merging (or set ignore-inline-allow)."
    fi
  fi
fi

# gitleaks ALWAYS reads .gitleaksignore from the scanned working tree, on top
# of --gitleaks-ignore-path: overwrite the checked-out copy with the trusted
# one (or empty it). Only the working tree changes: the history under scan is
# read from git objects.
if [[ -e .gitleaksignore ]]; then
  cp "$config_dir/.gitleaksignore" .gitleaksignore
fi

args=(
  git --redact -v --exit-code=1
  --config "$config_dir/gitleaks.toml"
  --gitleaks-ignore-path "$config_dir/.gitleaksignore"
)
if [[ "$IGNORE_INLINE_ALLOW" == true ]]; then
  args+=(--ignore-gitleaks-allow)
fi
# No trailing space when the range is empty: gitleaks splits --log-opts on
# spaces, and the resulting empty argument makes `git log` yield nothing. The
# scan then "passes" having read 0 bytes.
args+=(
  --report-format=sarif "--report-path=$REPORT_PATH"
  "--log-opts=--no-merges${range:+ $range}"
)

echo "Scanning: ${range:-all fetched history} (config from ${trusted:-gitleaks defaults})"
gitleaks "${args[@]}"
