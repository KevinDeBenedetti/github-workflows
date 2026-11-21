#!/usr/bin/env bats
# Tests for .github/actions/notify-deployment/notify-deployment.sh: the job
# summary written after a deployment.

SCRIPT="$BATS_TEST_DIRNAME/../.github/actions/notify-deployment/notify-deployment.sh"

setup() {
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md"
  export APP_NAME=my-app-dev ENVIRONMENT=development STATUS=success VERSION=v1.2.3
  export RUN_URL=https://github.com/o/r/actions/runs/7
  export APP_URL='' ARGOCD_URL='' INFRA_COMMIT_URL='' INFRA_LINK_LABEL='Infra commit'
}

summary() { cat "$GITHUB_STEP_SUMMARY"; }

@test "a successful deployment: title, status, environment, version and the run link" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(summary)" = "$(printf '%s\n' \
    '### ✅ Deployment my-app-dev' \
    '' \
    '| Property | Value |' \
    '| :--- | :--- |' \
    '| **Status** | ✅ success |' \
    '| **Environment** | `development` |' \
    '| **Version** | `v1.2.3` |' \
    '' \
    '**Monitoring:**' \
    '- 📊 [Workflow run logs](https://github.com/o/r/actions/runs/7)')" ]
}

@test "any other status shows the failure icon" {
  STATUS=failure run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$(summary)" == '### ❌ Deployment my-app-dev'* ]]
  summary | grep -qxF '| **Status** | ❌ failure |'
}

@test "the application URL gets https:// when it has no scheme, and keeps its own otherwise" {
  APP_URL=app.example.com run bash "$SCRIPT"
  summary | grep -qxF '| **URL** | [app.example.com](https://app.example.com) |'
  rm "$GITHUB_STEP_SUMMARY"
  APP_URL=http://app.example.com run bash "$SCRIPT"
  summary | grep -qxF '| **URL** | [http://app.example.com](http://app.example.com) |'
}

@test "the ArgoCD and infra links appear only when set, the infra link under its label" {
  ARGOCD_URL=https://argocd.example.com/applications/my-app-dev \
    INFRA_COMMIT_URL=https://github.com/o/infra/pull/9 INFRA_LINK_LABEL='Infra PR' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  summary | grep -qxF -- '- 🛰️ [View in ArgoCD](https://argocd.example.com/applications/my-app-dev)'
  summary | grep -qxF -- '- 📝 [Infra PR](https://github.com/o/infra/pull/9)'
}

@test "the summary is appended, never overwritten" {
  echo 'earlier step' > "$GITHUB_STEP_SUMMARY"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(head -n 1 "$GITHUB_STEP_SUMMARY")" = 'earlier step' ]
  summary | grep -qxF '### ✅ Deployment my-app-dev'
}
