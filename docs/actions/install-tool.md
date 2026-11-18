---
title: Action — install-tool
---

# Action — install-tool

Installs one of the tools this repository's actions download, at the version pinned
in the action's `tools.json`, after checking the download against the SHA-256 (or
commit) pinned next to it. The [`actionlint`](actionlint.md), [`bats`](bats.md),
[`check-docs-external-links`](check-docs-external-links.md),
[`kubeconform`](kubeconform.md), [`secret-scan`](secret-scan.md),
[`setup-claude-code`](setup-claude-code.md) and [`shellcheck`](shellcheck.md) actions
call it.

It is internal: it installs the tools of its manifest only, and takes no URL or
version from the caller. A version chosen by the caller could not be checked against
a pinned checksum.

## Usage

```yaml
steps:
  - uses: KevinDeBenedetti/github-workflows/.github/actions/install-tool@main
    with:
      tool: shellcheck

  - run: shellcheck --version
```

## Inputs

| Input  | Default      | Description                                                                                                   |
| ------ | ------------ | ------------------------------------------------------------------------------------------------------------- |
| `tool` | *(required)* | The tool to install: `actionlint`, `bats`, `claude-code`, `gitleaks`, `kubeconform`, `lychee` or `shellcheck` |

## Steps

1. Read the tool's entry in `tools.json` and pick the release asset for the runner (`amd64` or `arm64`)
2. Download it, with retries, and check it against the pinned SHA-256: a mismatch installs nothing
3. Take the program out of its archive into `$RUNNER_TEMP/<tool>`
4. Add that directory to `PATH`

Bats is a git install instead: its release tag is cloned, the clone is checked
against the pinned commit, and its own installer runs.

## Notes

- Needs `bash`, `python3` (reads the manifest and opens `.tar.xz` archives), `curl`,
  `sha256sum` and `tar` on the runner, and `git` for Bats. No checkout, no `sudo`.
- Linux runners, `amd64` or `arm64`.
- The manifest, `.github/actions/install-tool/tools.json`, is the only place a pin
  lives. Renovate bumps a version there; CI then fails closed until
  `scripts/update-tool-checksums.py` refreshes the checksums.
- The `CI — Tool checksums` job downloads every asset again for both architectures
  when the manifest changes; the installs of this repository's CI prove `amd64`.
