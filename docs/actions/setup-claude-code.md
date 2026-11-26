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
  - uses: KevinDeBenedetti/github-workflows/.github/actions/setup-claude-code@v0.57.0 # x-release-please-version
  - run: claude --version
```

## Inputs

None.

## Steps

1. Refuse a runner that is not Linux with glibc
2. Call [`install-tool`](install-tool.md), which picks the release binary for the runner
   (`linux-x64` or `linux-arm64`), downloads it from `downloads.claude.ai`, checks it
   against the pinned SHA-256 and adds its directory to `PATH`

## Notes

- No version input: a version chosen by the caller could not be checked against a
  pinned checksum. The version follows the release of this repository you pin.
- The pinned SHA-256 values are the ones listed in the release's signed
  `manifest.json`. Renovate bumps the version in `install-tool`'s `tools.json`
  (npm datasource, `@anthropic-ai/claude-code`); CI then fails closed until
  `scripts/update-tool-checksums.py` refreshes the checksums.
- Needs `python3` on the runner, and runner 2.336.0 or newer for the nested
  `uses: $/…` call.
- The action sets no credential. The CLI authenticates with
  `CLAUDE_CODE_OAUTH_TOKEN` (subscription) or `ANTHROPIC_API_KEY` in the step that
  runs it.
