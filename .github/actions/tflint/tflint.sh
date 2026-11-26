#!/usr/bin/env bash
# Lint the Terraform module in TF_DIR with tflint.
#
# tflint reads the module's own .tflint.hcl; without one it runs its bundled
# Terraform ruleset. `--init` first installs the plugins that file declares
# (from GitHub releases: GITHUB_TOKEN, when set, lifts the API rate limit).
# tflint's exit code is the step's: 2 when it found an issue.
#
# Env: TF_DIR   the module's directory
set -euo pipefail

TF_DIR="${TF_DIR:-.}"
if [ ! -d "$TF_DIR" ]; then
  echo "::error::tflint: directory not found: $TF_DIR"
  exit 1
fi

tflint --chdir="$TF_DIR" --init
tflint --chdir="$TF_DIR" --format=compact
