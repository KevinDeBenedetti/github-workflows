#!/usr/bin/env bash
# Keep prek's hook environments in a directory that outlives the job, such as
# a volume mounted into a self-hosted runner pod, instead of the GitHub cache.
#
#   prek-home.sh select   export PREK_HOME to the store of this prek config
#   prek-home.sh clean    delete the stores no run has used for MAX_AGE_DAYS
#
# One store per config. After a successful run, prek-action runs
# `prek cache gc`, which keeps only what the config files it has seen still
# need, and drops the configs it cannot find. In a store shared by several
# configs, a run would delete the environments of every config missing from
# its own checkout, possibly while another runner is using them. Runs of the
# same config need the same environments, so they share a store: prek locks
# it itself (`<store>/.lock`) while it clones, installs and collects garbage.
#
# What flock guards is the cleanup. Next to each store `<root>/<key>/` sits a
# lock file `<root>/<key>.lock`, whose modification time is the store's last
# use. `select` takes a shared lock to touch it. `clean` takes an exclusive
# lock without waiting and checks the age again before it deletes. So a store
# is never deleted between a run choosing it and the run starting to use it.
#
# Environment:
#   PREK_HOME_ROOT  absolute path of the directory holding the stores (required)
#   CONFIG_DIR      directory holding the prek config (default: .)
#   PREK_VERSION    prek release the job installs, part of the key (select)
#   MAX_AGE_DAYS    days a store may stay unused before clean deletes it (default: 14)
#   GITHUB_ENV, GITHUB_OUTPUT  set by the runner (select writes PREK_HOME and `path`)
set -euo pipefail

fail() {
  echo "::error::$*"
  exit 1
}

mode="${1:-}"
root="${PREK_HOME_ROOT:-}"
config_dir="${CONFIG_DIR:-.}"
version="${PREK_VERSION:-}"
max_age_days="${MAX_AGE_DAYS:-14}"

[[ "$mode" == select || "$mode" == clean ]] || fail "usage: prek-home.sh select|clean (got '$mode')"
[[ "$root" == /* ]] || fail "prek-home must be an absolute path (got '$root')"
while [[ "$root" == */ ]]; do root="${root%/}"; done
[[ -n "$root" ]] || fail "prek-home must be a directory of its own, not /"
[[ -d "$root" ]] || fail "prek-home $root is not a directory: mount a volume there (see the ci-prek docs)"
[[ -w "$root" ]] || fail "prek-home $root is not writable by uid $(id -u)"
command -v flock >/dev/null || fail "flock not found: the runner needs util-linux"

# The store key: what makes two sets of hook environments interchangeable.
# That is the prek release, the runner's platform and every prek config under
# the working directory, nested projects included (prek's workspace mode).
fingerprint() {
  printf 'prek %s\n%s %s\n' "$version" "${RUNNER_OS:-$(uname -s)}" "${RUNNER_ARCH:-$(uname -m)}"
  (
    cd "$config_dir"
    find . \( -name .git -o -name node_modules \) -prune -o -type f \
      \( -name prek.toml -o -name .prek.toml -o -name .pre-commit-config.yaml -o -name .pre-commit-config.yml \) \
      -print | LC_ALL=C sort | while IFS= read -r file; do
      sum="$(sha256sum <"$file")"
      printf '%s %s\n' "${sum%% *}" "$file"
    done
  )
}

select_store() {
  [[ -n "$version" ]] || fail "prek-version is empty"
  [[ -d "$config_dir" ]] || fail "working-directory $config_dir does not exist"
  command -v sha256sum >/dev/null || fail "sha256sum not found: the runner needs coreutils"

  local key store lock state
  key="$(fingerprint | sha256sum)"
  key="${key:0:16}"
  store="$root/$key"
  lock="$store.lock"

  # A shared lock: runs of the same config do not wait for each other, only
  # for a cleanup that is deleting this store (then it starts empty).
  exec 9>>"$lock"
  flock -s 9
  touch "$lock"
  if [[ -d "$store" ]]; then
    state="reusing the hook environments of earlier runs"
  else
    state="new: this run installs every hook environment"
  fi
  mkdir -p "$store"
  exec 9>&-

  echo "PREK_HOME=$store" >>"${GITHUB_ENV:?GITHUB_ENV is not set}"
  echo "path=$store" >>"${GITHUB_OUTPUT:-/dev/null}"
  echo "prek store $store ($state)."
}

# stale FILE: FILE was last modified more than MAX_AGE_DAYS days ago.
stale() {
  [[ -n "$(find "$1" -maxdepth 0 -mmin "+$((max_age_days * 24 * 60))" 2>/dev/null)" ]]
}

clean_stores() {
  [[ "$max_age_days" =~ ^[1-9][0-9]{0,3}$ ]] ||
    fail "max-age-days must be a whole number from 1 to 9999 (got '$max_age_days')"

  local dir name lock status kept=0 deleted=0
  for dir in "$root"/*/; do
    [[ -d "$dir" ]] || continue # no store at all: the glob stays as written
    dir="${dir%/}"
    name="${dir##*/}"
    # Only the stores `select` creates: prek-home may hold other things.
    [[ "$name" =~ ^[0-9a-f]{16}$ ]] || continue
    lock="$dir.lock"
    # A store without its lock file starts its countdown now.
    [[ -e "$lock" ]] || touch "$lock"
    if ! stale "$lock"; then
      kept=$((kept + 1))
      continue
    fi

    status=0
    (
      exec 9>>"$lock"
      flock -xn 9 || exit 10 # a run is choosing this store right now
      stale "$lock" || exit 10 # a run chose it since the first look
      # Go's module cache is read-only: rm needs write access to empty it.
      chmod -R u+w "$dir" 2>/dev/null
      rm -rf "$dir" || exit 1
      rm -f "$lock"
    ) || status=$?
    case "$status" in
      0)
        echo "Deleted the prek store $dir, unused for over $max_age_days days."
        deleted=$((deleted + 1))
        ;;
      10) kept=$((kept + 1)) ;;
      *)
        echo "::warning::Could not delete the prek store $dir."
        kept=$((kept + 1))
        ;;
    esac
  done

  local free
  free="$(df -Ph "$root" | awk 'NR == 2 { print $4 " free of " $2 }')"
  echo "prek stores in $root: $deleted deleted, $kept kept; ${free:-free space unknown}."
}

case "$mode" in
  select) select_store ;;
  clean) clean_stores ;;
esac
