#!/usr/bin/env bats
# Tests for .github/actions/lighthouse-results/lighthouse-results.sh

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/lighthouse-results/lighthouse-results.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p bin tmp .lighthouse .lighthouseci
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  # The script's mktemp directory stays inside the test's own directory.
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  export STUB_DIR="$BATS_TEST_TMPDIR"
  stub_curl
  fixtures
}

# A fake curl. It logs every call (arguments, then method and URL) and the
# header files it reads, serves health.json for the audited site and
# commit-<ref>.json for the commits API, and keeps every status it is sent.
# A refuse-statuses file makes it answer the statuses API with an error.
stub_curl() {
  cat > bin/curl <<'EOF'
#!/usr/bin/env bash
out=- method=GET data="" url=""
printf '%s\n' "$*" >> "$STUB_DIR/curl-args.log"
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -X) method="$2"; shift 2 ;;
    --data-binary) data="${2#@}"; shift 2 ;;
    -H) case "$2" in @*) cat "${2#@}" >> "$STUB_DIR/curl-headers.log" ;; esac; shift 2 ;;
    --retry | --retry-delay | --max-time) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
printf '%s %s\n' "$method" "$url" >> "$STUB_DIR/curl.log"
# emit: the response body, into the -o file or on stdout.
emit() { if [ "$out" = - ]; then cat; else cat > "$out"; fi; }
case "$url" in
  https://site.test/*)
    emit < "$STUB_DIR/health.json"
    ;;
  */commits/*)
    ref="${url##*/commits/}"
    if [ -f "$STUB_DIR/commit-$ref.json" ]; then
      emit < "$STUB_DIR/commit-$ref.json"
    else
      printf '{"message":"No commit found for SHA: %s"}' "$ref" | emit
      exit 22
    fi
    ;;
  */statuses/*)
    jq -c . "$data" >> "$STUB_DIR/statuses.jsonl"
    if [ -f "$STUB_DIR/refuse-statuses" ]; then
      printf '{"message":"Resource not accessible by integration"}' | emit
      exit 22
    fi
    printf '{}' | emit
    ;;
esac
EOF
  chmod +x bin/curl
}

# Two pages measured three times each, as lhci leaves them: /en passes (only a
# warn assertion fails), /fr redirects to /fr/ and misses the performance
# minimum. Only the median runs are read: the other entry points at a report
# that does not exist.
fixtures() {
  cat > .lighthouse/en.json <<'EOF'
{"requestedUrl":"https://site.test/en","finalUrl":"https://site.test/en","categories":{"performance":{"title":"Performance","score":0.72},"accessibility":{"title":"Accessibility","score":1},"best-practices":{"title":"Best Practices","score":0.96},"seo":{"title":"SEO","score":1}}}
EOF
  cat > .lighthouse/fr.json <<'EOF'
{"requestedUrl":"https://site.test/fr","finalUrl":"https://site.test/fr/","categories":{"performance":{"title":"Performance","score":0.38},"accessibility":{"title":"Accessibility","score":null},"best-practices":{"title":"Best Practices","score":1},"seo":{"title":"SEO","score":1}}}
EOF
  jq -n --arg dir "$PWD/.lighthouse" '[
    {url: "https://site.test/en", isRepresentativeRun: false, jsonPath: "/nowhere/en-1.json"},
    {url: "https://site.test/en", isRepresentativeRun: true, jsonPath: "\($dir)/en.json"},
    {url: "https://site.test/fr", isRepresentativeRun: true, jsonPath: "\($dir)/fr.json"}
  ]' > .lighthouse/manifest.json
  cat > .lighthouseci/assertion-results.json <<'EOF'
[
  {"auditId": "categories", "auditProperty": "performance", "level": "error", "passed": true, "url": "https://site.test/en"},
  {"auditId": "uses-http2", "level": "warn", "passed": false, "url": "https://site.test/en"},
  {"auditId": "categories", "auditProperty": "performance", "level": "error", "passed": false, "url": "https://site.test/fr/"},
  {"auditId": "categories", "auditProperty": "seo", "level": "error", "passed": true, "url": "https://site.test/fr/"}
]
EOF
}

# results [VAR=value...]: run the script as the action does, against the fake curl.
results() {
  env -u GITHUB_API_URL -u GITHUB_SERVER_URL -u VERSION_URL -u SHA -u TARGET_URL \
    GITHUB_TOKEN=secret-token-123 GITHUB_REPOSITORY=o/r GITHUB_SHA=abc123 GITHUB_RUN_ID=42 \
    GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md" "$@" \
    bash "$SCRIPT"
}

# status_of CONTEXT FIELD: a field of the status posted for CONTEXT.
status_of() {
  jq -r --arg context "$1" "select(.context == \$context) | .$2" statuses.jsonl
}

@test "writes one summary row per page, the failed category marked" {
  run results
  [ "$status" -eq 0 ]
  grep -qxF '| Page | Performance | Accessibility | Best Practices | SEO | Result |' summary.md
  grep -qxF '| /en | 72 | 100 | 96 | 100 | ✅ |' summary.md
  grep -qxF '| /fr | ❌ 38 | n/a | 100 | 100 | ❌ 1 failed |' summary.md
}

@test "posts one status per page on the run's commit, linking the run" {
  run results
  [ "$status" -eq 0 ]
  [ "$(grep -c '^POST https://api.github.com/repos/o/r/statuses/abc123$' curl.log)" -eq 2 ]
  [ "$(status_of lighthouse/en state)" = success ]
  [ "$(status_of lighthouse/en description)" = 'Performance: 72, Accessibility: 100, Best Practices: 96, SEO: 100' ]
  [ "$(status_of lighthouse/en target_url)" = https://github.com/o/r/actions/runs/42 ]
}

@test "a page fails on the error assertions of its final URL only" {
  run results
  [ "$status" -eq 0 ]
  [ "$(status_of lighthouse/fr state)" = failure ]
  [ "$(status_of lighthouse/fr description)" = 'Failed 1 assertion(s) — Performance: 38, Accessibility: n/a, Best Practices: 100, SEO: 100' ]
}

@test "target-url and context-prefix shape every status" {
  run results TARGET_URL=https://github.com/o/r/actions/runs/42/artifacts/7 CONTEXT_PREFIX=lhci/prod
  [ "$status" -eq 0 ]
  [ "$(status_of lhci/prod/en target_url)" = https://github.com/o/r/actions/runs/42/artifacts/7 ]
  [ "$(status_of lhci/prod/fr state)" = failure ]
}

@test "reads a report next to its manifest when jsonPath is stale" {
  jq '(.[] | select(.isRepresentativeRun) | .jsonPath) |= "/nowhere/" + (split("/") | last)' \
    .lighthouse/manifest.json > manifest.json
  mv manifest.json .lighthouse/manifest.json
  run results POST_STATUSES=false
  [ "$status" -eq 0 ]
  grep -qxF '| /en | 72 | 100 | 96 | 100 | ✅ |' summary.md
}

@test "post-statuses false writes the summary only" {
  run results POST_STATUSES=false
  [ "$status" -eq 0 ]
  grep -qF '| /fr |' summary.md
  [ ! -e curl.log ]
}

@test "no manifest: says so in the summary and posts nothing" {
  rm .lighthouse/manifest.json
  run results
  [ "$status" -eq 0 ]
  grep -qxF '_No report produced._' summary.md
  [ ! -e curl.log ]
}

@test "version-url: posts on the commit of the release the site runs" {
  printf '{"status":"ok","version":"v1.4.0"}' > health.json
  printf '{"sha":"def456"}' > commit-v1.4.0.json
  run results VERSION_URL=https://site.test/api/health
  [ "$status" -eq 0 ]
  grep -qxF 'GET https://site.test/api/health' curl.log
  grep -qxF 'GET https://api.github.com/repos/o/r/commits/v1.4.0' curl.log
  [ "$(grep -c '^POST https://api.github.com/repos/o/r/statuses/def456$' curl.log)" -eq 2 ]
}

@test "version-url: a bare version is also looked up with a v prefix" {
  printf '{"version":"1.4.0"}' > health.json
  printf '{"sha":"def456"}' > commit-v1.4.0.json
  run results VERSION_URL=https://site.test/api/health
  [ "$status" -eq 0 ]
  grep -qxF 'GET https://api.github.com/repos/o/r/commits/1.4.0' curl.log
  grep -qxF 'GET https://api.github.com/repos/o/r/commits/v1.4.0' curl.log
  grep -qxF 'POST https://api.github.com/repos/o/r/statuses/def456' curl.log
}

@test "version-url: no release version skips the statuses with a warning" {
  printf '{"version":"unknown"}' > health.json
  run results VERSION_URL=https://site.test/api/health
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::https://site.test/api/health names no release tag"* ]]
  [ "$(grep -c '/statuses/' curl.log)" -eq 0 ]
  grep -qF '| /en | 72 |' summary.md
}

@test "version-url: an answer that is not tag-shaped is neither looked up nor printed" {
  printf '{"version":"v1\\n::add-mask::x"}' > health.json
  run results VERSION_URL=https://site.test/api/health
  [ "$status" -eq 0 ]
  [[ "$output" != *"add-mask"* ]]
  [ "$(grep -c '/commits/' curl.log)" -eq 0 ]
}

@test "a refused status fails the step, after trying every page" {
  touch refuse-statuses
  run results
  [ "$status" -eq 1 ]
  [ "$(grep -c '/statuses/' curl.log)" -eq 2 ]
  [[ "$output" == *"statuses: write"* ]]
  [[ "$output" == *"Resource not accessible by integration"* ]]
}

@test "the token goes through a header file, never on the command line" {
  run results
  [ "$status" -eq 0 ]
  [ "$(grep -c 'secret-token-123' curl-args.log)" -eq 0 ]
  grep -qxF 'Authorization: Bearer secret-token-123' curl-headers.log
}

@test "posting needs a token" {
  run results GITHUB_TOKEN=
  [ "$status" -ne 0 ]
  [[ "$output" == *"GITHUB_TOKEN is required"* ]]
}
