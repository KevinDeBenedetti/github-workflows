#!/usr/bin/env bash
# Run ShellCheck on every *.sh file under the current directory, each checked
# as the shell it declares.
#
# A script declares its dialect with a `# shellcheck shell=` directive, or with
# a shebang naming sh, bash, dash, ksh or busybox (`#!/usr/bin/env [-S] [-opts]
# <shell>` included). Declared scripts are checked as that dialect: forcing
# --shell=bash would hide POSIX-sh portability issues in #!/bin/sh scripts.
# The others, scripts with no shebang (sourced libraries) and scripts whose
# shebang names a shell ShellCheck cannot parse (zsh, fish…, which would fail
# with SC1071), are checked as DEFAULT_SHELL, otherwise SC2148.
#
# Never descends into .git, node_modules or .venv. Exits 1 when either pass
# reports an issue at SEVERITY or above.
#
# Env: SEVERITY        error | warning | info | style (default warning)
#      EXCLUDE_PATHS   one glob passed to find -not -path (default */test_helper/*)
#      DEFAULT_SHELL   sh | bash | dash | ksh | busybox (default bash)
set -euo pipefail

SEVERITY="${SEVERITY:-warning}"
EXCLUDE_PATHS="${EXCLUDE_PATHS-*/test_helper/*}"
DEFAULT_SHELL="${DEFAULT_SHELL:-bash}"

fail() {
  echo "::error::$*"
  exit 1
}

case "$SEVERITY" in
  error | warning | info | style) ;;
  *) fail "severity must be error, warning, info or style, not '$SEVERITY'" ;;
esac
case "$DEFAULT_SHELL" in
  sh | bash | dash | ksh | busybox) ;;
  *) fail "default-shell must be sh, bash, dash, ksh or busybox, not '$DEFAULT_SHELL'" ;;
esac

# shebang_dialect FILE: the shell FILE's shebang names, empty without one.
shebang_dialect() {
  local line words i
  IFS= read -r line < "$1" || true
  [[ $line == '#!'* ]] || return 0
  read -ra words <<< "${line#\#!}"
  ((${#words[@]})) || return 0
  i=0
  # `#!/usr/bin/env [-S] [-opts] shell`: skip env and its options.
  if [[ ${words[0]##*/} == env ]]; then
    i=1
    while [[ ${words[i]:-} == -* ]]; do i=$((i + 1)); done
  fi
  echo "${words[i]##*/}"
}

DECLARED=()
UNDECLARED=()
while IFS= read -r -d '' f; do
  if grep -qE '^#[[:space:]]*shellcheck[[:space:]]+shell=' "$f"; then
    DECLARED+=("$f")
    continue
  fi
  case "$(shebang_dialect "$f")" in
    sh | bash | dash | ksh | busybox) DECLARED+=("$f") ;;
    *) UNDECLARED+=("$f") ;;
  esac
done < <(find . \
  \( -path ./.git -o -path '*/node_modules' -o -path '*/.venv' \) -prune -o \
  -type f -name '*.sh' -not -path "$EXCLUDE_PATHS" -print0 | sort -z)

status=0
if [ "${#DECLARED[@]}" -gt 0 ]; then
  shellcheck --severity="$SEVERITY" --format=gcc "${DECLARED[@]}" || status=1
fi
if [ "${#UNDECLARED[@]}" -gt 0 ]; then
  shellcheck --severity="$SEVERITY" --shell="$DEFAULT_SHELL" --format=gcc "${UNDECLARED[@]}" || status=1
fi
echo "Checked $((${#DECLARED[@]} + ${#UNDECLARED[@]})) script(s)."
exit "$status"
