---
title: Action — setup-claude-code
---

# Action — setup-claude-code

Installs the Claude Code CLI (`claude`) on a Linux runner, pinned to one version and
checked against the SHA-256 recorded in this repository for each architecture. Used
by `pr-description.yml`.

## Usage

```yaml
steps:
  - uses: KevinDeBenedetti/github-workflows/.github/actions/setup-claude-code@main

  - run: claude --version
```

## Inputs

None.

## Steps

1. Pick the release binary for the runner: `linux-x64` or `linux-arm64` (glibc only)
2. Download it from `downloads.claude.ai` and check it against the pinned SHA-256
3. Add its directory to `PATH`

## Notes

- No version input: a version chosen by the caller could not be checked against a
  pinned checksum. The version follows the release of this repository you pin.
- The pinned SHA-256 values are the ones listed in the release's signed
  `manifest.json`. Renovate bumps the version (npm datasource,
  `@anthropic-ai/claude-code`); the job then fails closed until
  `scripts/update-tool-checksums.py` refreshes the checksums.
- The action sets no credential. The CLI authenticates with
  `CLAUDE_CODE_OAUTH_TOKEN` (subscription) or `ANTHROPIC_API_KEY` in the step that
  runs it.
