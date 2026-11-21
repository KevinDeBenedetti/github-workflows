#!/usr/bin/env bash
# Append a Markdown summary of a deployment to the job summary: status,
# environment, version, then the links that were given.
#
# Env: APP_NAME, ENVIRONMENT, VERSION
#      STATUS             "success" shows ✅, anything else ❌
#      APP_URL            application URL, https:// added when it has no scheme (optional)
#      ARGOCD_URL         the application in ArgoCD (optional)
#      INFRA_COMMIT_URL   the infra change behind the deployment (optional)
#      INFRA_LINK_LABEL   text of that link
#      RUN_URL            this workflow run
#      GITHUB_STEP_SUMMARY
set -euo pipefail

ICON="✅"
if [ "$STATUS" != "success" ]; then
  ICON="❌"
fi

{
  echo "### ${ICON} Deployment ${APP_NAME}"
  echo ""
  echo "| Property | Value |"
  echo "| :--- | :--- |"
  echo "| **Status** | ${ICON} ${STATUS} |"
  echo "| **Environment** | \`${ENVIRONMENT}\` |"
  echo "| **Version** | \`${VERSION}\` |"

  if [ -n "${APP_URL:-}" ]; then
    case "$APP_URL" in
      http://* | https://*) HREF="$APP_URL" ;;
      *) HREF="https://${APP_URL}" ;;
    esac
    echo "| **URL** | [${APP_URL}](${HREF}) |"
  fi

  echo ""
  echo "**Monitoring:**"

  if [ -n "${ARGOCD_URL:-}" ]; then
    echo "- 🛰️ [View in ArgoCD](${ARGOCD_URL})"
  fi
  if [ -n "${INFRA_COMMIT_URL:-}" ]; then
    echo "- 📝 [${INFRA_LINK_LABEL}](${INFRA_COMMIT_URL})"
  fi
  echo "- 📊 [Workflow run logs](${RUN_URL})"
} >> "$GITHUB_STEP_SUMMARY"
