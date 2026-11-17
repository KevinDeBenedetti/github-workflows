# A fake curl that plays the GitHub REST API for the Bats tests of the scripts
# that call it (cleanup-runs, cleanup-deployments, propagate-release,
# pr-description). Load it with `load helpers/fake-github`.
#
# fake_github PREFIX ROUTES
#   Installs $BATS_TEST_TMPDIR/bin/curl; the test puts that directory first in
#   PATH and exports STUB_DIR. Each request is logged in STUB_DIR:
#     curl.log          "METHOD PATH" (PATH: the URL without PREFIX), plus
#                       " DATA" for a -d body; line N is request N
#     sent/N.json       the --data-binary @file body of request N
#     curl-args.log     the command line, to prove no token is on it
#     curl-headers.log  the headers, from -H @file and -H 'Name: value'
#   then ROUTES, a bash snippet (usually a `case "$method $path"`), answers it
#   with these variables and functions:
#     method url path data seq page   data: the --data-binary file or -d value;
#                                     page: the page= query value
#     reply STATUS BODY               BODY to the -o file; STATUS printed for
#                                     -w, or exit 22 from 400 on with
#                                     --fail-with-body, like curl
#     reply_file NAME STATUS          STUB_DIR/NAME with STATUS, else a 404
fake_github() {
  local prefix="$1" routes="$2"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  {
    cat <<'HEAD'
#!/usr/bin/env bash
out=/dev/stdout method=GET url="" data="" body_file="" write_out=false fail_with_body=false
printf '%s\n' "$*" >> "$STUB_DIR/curl-args.log"
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -X) method="$2"; shift 2 ;;
    -w) write_out=true; shift 2 ;;
    -d) data="$2"; shift 2 ;;
    --data-binary) body_file="${2#@}"; data="$body_file"; shift 2 ;;
    -H)
      case "$2" in
        @*) cat "${2#@}" >> "$STUB_DIR/curl-headers.log" ;;
        *) printf '%s\n' "$2" >> "$STUB_DIR/curl-headers.log" ;;
      esac
      shift 2 ;;
    --retry | --retry-delay | --max-time) shift 2 ;;
    --fail-with-body) fail_with_body=true; shift ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
HEAD
    # Written into the stub as text: url only exists when the stub runs.
    # shellcheck disable=SC2016
    printf 'path="${url#%s}"\n' "$prefix"
    cat <<'TAIL'
seq=$(( $(wc -l < "$STUB_DIR/curl.log" 2> /dev/null || echo 0) + 1 ))
if [ -n "$data" ] && [ -z "$body_file" ]; then
  printf '%s %s %s\n' "$method" "$path" "$data" >> "$STUB_DIR/curl.log"
else
  printf '%s %s\n' "$method" "$path" >> "$STUB_DIR/curl.log"
fi
if [ -n "$body_file" ]; then
  mkdir -p "$STUB_DIR/sent"
  cp "$body_file" "$STUB_DIR/sent/$seq.json"
fi
page="$(printf '%s' "$path" | sed -n 's/.*[?&]page=\([0-9]*\).*/\1/p')"
reply() {
  printf '%s' "$2" > "$out"
  if [ "$write_out" = true ]; then
    printf '%s' "$1"
  elif [ "$fail_with_body" = true ] && [ "$1" -ge 400 ]; then
    exit 22
  fi
  exit 0
}
reply_file() {
  if [ -f "$STUB_DIR/$1" ]; then
    reply "$2" "$(cat "$STUB_DIR/$1")"
  else
    reply 404 '{"message":"Not Found"}'
  fi
}
TAIL
    printf '%s\n' "$routes"
    printf '%s\n' "reply 404 '{\"message\":\"Not Found\"}'"
  } > "$BATS_TEST_TMPDIR/bin/curl"
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
}
