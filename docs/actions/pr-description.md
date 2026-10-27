---
title: Action — pr-description
---

# Action — pr-description

Writes the description of the current pull request with Claude Code and stores it in
a managed block at the top of the pull request body. It is the engine of the
[`pr-description` workflow](../workflows/pr-description.md), which most callers
should use instead.

## Usage

The job needs `contents: read` and `pull-requests: write`. The runner needs `curl`,
`git`, `jq` and `python3`, but no GitHub CLI: GitHub-hosted runners and the
`actions-runner` image used by self-hosted ARC runners have them.

```yaml
steps:
  - uses: actions/checkout@v7
    with:
      ref: ${{ github.event.pull_request.head.sha }}
      fetch-depth: 0
      persist-credentials: false

  - uses: KevinDeBenedetti/github-workflows/.github/actions/setup-claude-code@main

  - uses: KevinDeBenedetti/github-workflows/.github/actions/pr-description@main
    with:
      claude-code-oauth-token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
      model: opus
```

## Inputs

| Input                     | Type   | Default                       | Description                                                 |
| ------------------------- | ------ | ----------------------------- | ----------------------------------------------------------- |
| `claude-code-oauth-token` | string | — (required)                  | Token from `claude setup-token`                             |
| `model`                   | string | — (required)                  | Claude model: an alias (`opus`, `sonnet`, …) or a full name |
| `effort`                  | string | `''`                          | Claude Code effort level; empty for Claude Code's default   |
| `language`                | string | `English`                     | Language of the description                                 |
| `max-diff-bytes`          | string | `100000`                      | Size cap of the diff sent to Claude, in bytes               |
| `github-token`            | string | the job's `GITHUB_TOKEN`      | Token allowed to edit the pull request                      |
| `pr-number`               | string | from the `pull_request` event | Pull request to update                                      |
| `base-sha`                | string | from the `pull_request` event | Base commit of the diff                                     |
| `head-sha`                | string | from the `pull_request` event | Head commit of the diff                                     |
| `title`                   | string | from the `pull_request` event | Pull request title                                          |

## Steps

1. `collect-context.sh` prints the title, the commit messages, the diffstat and the
   diff (lockfiles left out, cut at `max-diff-bytes`)
2. `write-description.sh` runs `claude -p` with the model, the effort and the system
   prompt in `system-prompt.md`, with no tool, from empty working and configuration
   directories. Only this step gets the Claude token
3. `update-body.sh` reads the current body through the REST API with `curl`,
   `merge-body.py` replaces the managed block or puts one on top, and the body is
   saved only when it changed. Only this step gets the GitHub token, through a
   header file rather than a command line

## The managed block

```markdown
<!-- pr-description:start (rewritten on every push: write your own notes outside this block) -->
The generated description.
<!-- pr-description:end -->
```

Write your own notes, a pull request template or `Closes #12` outside the block:
they are kept as they are. Delete the block to get a fresh one on top at the next
push.
