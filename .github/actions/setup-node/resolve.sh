#!/usr/bin/env bash
# Resolve everything setup-node and its callers need to know about a Node.js
# project, from its files: package manager, lockfile, pnpm version, framework,
# and the commands that go with them. Read once here, so that no caller
# branches on the package manager again.
#
# Package manager: INPUT_PM, or with "auto" the nearest lockfile, the working
# directory first, then the repository root (workspaces keep one lockfile at
# the root): bun.lockb / bun.lock → bun, package-lock.json → npm, otherwise
# pnpm.
# Framework: INPUT_FRAMEWORK, or with "auto" the config files of the working
# directory: next.config.* → next, nuxt.config.* → nuxt, otherwise vite.
#
# Environment:
#   DIR                 working directory of the project (default ".")
#   INPUT_PM            pnpm | bun | npm | auto (default auto)
#   INPUT_PNPM_VERSION  pnpm version to install, empty to read packageManager
#   INPUT_FRAMEWORK     next | nuxt | vite | auto (default auto)
#   GITHUB_OUTPUT       set by the runner; receives:
#     pm             pnpm | bun | npm
#     pnpm-version   version for pnpm/action-setup, empty when package.json's
#                    packageManager field names it
#     package-json   the package.json pnpm/action-setup reads
#     npm-lockfile   package-lock.json path (npm only)
#     npm-dir        directory `npm ci` runs in
#     lockfile       the lockfile the dependency caches are keyed on
#     run-command    runs a package.json script: "pnpm", "npm run" or "bun run"
#     audit-command  audits the lockfile at the high level
#     framework      next | nuxt | vite
#     build-output   the framework's build directory, relative to DIR
set -euo pipefail

DIR="${DIR:-.}"
INPUT_PM="${INPUT_PM:-auto}"
INPUT_PNPM_VERSION="${INPUT_PNPM_VERSION:-}"
INPUT_FRAMEWORK="${INPUT_FRAMEWORK:-auto}"

fail() {
  echo "::error::$*" >&2
  exit 1
}

# Workspaces (npm, pnpm, bun) keep a single lockfile at the repository root,
# so a lockfile in the working directory wins, then the root's.
find_lock() {
  local d n
  for d in "$DIR" "."; do
    for n in "$@"; do
      if [[ -f "$d/$n" ]]; then
        echo "$d/$n"
        return
      fi
    done
  done
}

if [[ "$INPUT_PM" != auto ]]; then
  pm="$INPUT_PM"
else
  case "$(find_lock bun.lockb bun.lock package-lock.json pnpm-lock.yaml)" in
    */bun.lock | */bun.lockb) pm=bun ;;
    */package-lock.json) pm=npm ;;
    *) pm=pnpm ;;
  esac
fi
case "$pm" in
  pnpm | bun | npm) ;;
  *) fail "unsupported package-manager '$pm' (expected pnpm, bun, npm or auto)" ;;
esac

# npm: cache and `npm ci` from the lockfile's directory (the workspace root
# when the working directory is a workspace member).
npm_lockfile=""
npm_dir="$DIR"
if [[ "$pm" == npm ]]; then
  npm_lockfile="$(find_lock package-lock.json)"
  [[ -n "$npm_lockfile" ]] ||
    fail "package-manager npm needs a package-lock.json in '$DIR' or the repository root"
  npm_dir="$(dirname "$npm_lockfile")"
fi

# pnpm version: explicit input > packageManager field > pinned fallback. When
# packageManager is set, the version must stay EMPTY and pnpm/action-setup is
# pointed at that package.json instead.
pnpm_version="$INPUT_PNPM_VERSION"
package_json="package.json"
if [[ "$pm" == pnpm && -z "$pnpm_version" ]]; then
  # A pinned release rather than `latest`, so a freshly published (or
  # compromised) pnpm never reaches CI unreviewed. Renovate bumps it.
  # renovate: datasource=npm depName=pnpm
  PNPM_VERSION="12.14.0"
  pnpm_version="$PNPM_VERSION"
  for f in "$DIR/package.json" "package.json"; do
    if [[ -f "$f" ]] && grep -qE '"packageManager"[[:space:]]*:[[:space:]]*"pnpm@' "$f"; then
      pnpm_version=""
      package_json="${f#./}"
      break
    fi
  done
fi

# The lockfile the caches are keyed on: the one the package manager reads.
# Hashing only "$DIR/<lockfile>" hashed nothing for a workspace member (the
# lockfile sits at the root), so every member of every dependency set shared
# one key, saved once, then never refreshed. Falls back to the (absent)
# working-directory path, an empty hash.
case "$pm" in
  pnpm)
    lockfile="$(find_lock pnpm-lock.yaml)"
    lockfile="${lockfile:-$DIR/pnpm-lock.yaml}"
    run_command="pnpm"
    ;;
  bun)
    lockfile="$(find_lock bun.lock bun.lockb)"
    lockfile="${lockfile:-$DIR/bun.lock}"
    run_command="bun run"
    ;;
  npm)
    lockfile="$npm_lockfile"
    run_command="npm run"
    ;;
esac
lockfile="${lockfile#./}"
audit_command="$pm audit --audit-level=high"

framework="$INPUT_FRAMEWORK"
if [[ "$framework" == auto ]]; then
  if [[ -f "$DIR/next.config.ts" || -f "$DIR/next.config.js" || -f "$DIR/next.config.mjs" ]]; then
    framework=next
  elif [[ -f "$DIR/nuxt.config.ts" || -f "$DIR/nuxt.config.js" ]]; then
    framework=nuxt
  else
    framework=vite
  fi
fi
case "$framework" in
  next) build_output=".next" ;;
  nuxt) build_output=".output" ;;
  vite) build_output="dist" ;;
  *) fail "unsupported framework '$framework' (expected next, nuxt, vite or auto)" ;;
esac

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "pm=$pm"
    echo "pnpm-version=$pnpm_version"
    echo "package-json=$package_json"
    echo "npm-lockfile=$npm_lockfile"
    echo "npm-dir=$npm_dir"
    echo "lockfile=$lockfile"
    echo "run-command=$run_command"
    echo "audit-command=$audit_command"
    echo "framework=$framework"
    echo "build-output=$build_output"
  } >> "$GITHUB_OUTPUT"
fi
echo "📦 Package manager: $pm"
if [[ "$pm" == pnpm ]]; then
  echo "📌 pnpm version: ${pnpm_version:-from packageManager in $package_json}"
fi
echo "🏗️ Framework: $framework → build output: $DIR/$build_output"
