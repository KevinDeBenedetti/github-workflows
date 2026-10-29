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
| `language`                | string | `English`                     | Language of the text; the section headings stay in English  |
| `max-diff-bytes`          | string | `100000`                      | Size cap of each context block, in bytes; at most `3000000` |
| `github-token`            | string | the job's `GITHUB_TOKEN`      | Token allowed to edit the pull request                      |
| `pr-number`               | string | from the `pull_request` event | Pull request to update                                      |
| `base-sha`                | string | from the `pull_request` event | Base commit of the diff                                     |
| `head-sha`                | string | from the `pull_request` event | Head commit of the diff                                     |
| `title`                   | string | from the `pull_request` event | Pull request title                                          |

## Steps

1. `collect-context.sh` prints the title, the commit messages, the diffstat and the
   diff (lockfiles left out), each in a block cut at `max-diff-bytes`. The tags
   around a block end in a random suffix drawn for the run, so text in a commit or
   a file cannot close a block or open another. Git runs without external diff
   drivers or textconv filters
2. `write-description.sh` runs `claude -p` with the model, the effort and the system
   prompt in `system-prompt.md`, with no tool and no slash command, from empty
   working, configuration and home directories. Claude Code gets the Claude token
   and the runner's `PATH`, locale, time zone, proxy and CA certificate variables,
   nothing else from the job: no `GITHUB_TOKEN`, cloud credential or
   `ANTHROPIC_API_KEY`. Only this step gets the Claude token
3. `update-body.sh` reads the current body through the REST API with `curl`,
   `merge-body.py` filters the description (see [Filtered text](#filtered-text)),
   then replaces the managed block or puts one on top, and the body is saved only
   when it changed. Only this step gets the GitHub token, through a header file
   rather than a command line, and only for an `https://` `GITHUB_API_URL`

## The managed block

```markdown
<!-- pr-description:start (rewritten on every push: write your own notes outside this block) -->
## Summary

What the pull request changes and why.

## Changes

- **Area**: Change
<!-- pr-description:end -->
```

Write your own notes or `Closes #12` outside the block: they are kept as they are.
A pull request template that holds the block gets it filled in place (see
[Pull request template](../workflows/pr-description.md#pull-request-template));
otherwise the block goes on top of the body. Delete the block to get a fresh one
on top at the next push.

## Filtered text

The description is model output written from repository content, so
`merge-body.py` treats it as data before it reaches the body. Outside code spans
and fenced code blocks, it decodes HTML entities, removes HTML and images, turns
links into their text, and wraps `@mentions`, issue references and URLs in code,
to keep the generated text from notifying people, linking or closing issues on
merge, loading remote images or offering links to click. Control, zero-width and
bidirectional characters are dropped everywhere.
