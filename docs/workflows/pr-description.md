---
title: '`pr-description` workflow'
---

# `pr-description` workflow

Keeps the description of a pull request up to date with
[Claude Code](https://code.claude.com/docs/en/overview). Each time the pull request
is opened, reopened or receives a push, Claude reads its commits and its diff and
rewrites a managed block at the top of the description. The run uses your Claude
subscription (Pro, Max, Team or Enterprise), not API billing.

## Usage

```yaml
# .github/workflows/pr-description.yml  (in your repo)
name: PR description

on:
  pull_request:
    types: [opened, synchronize, reopened]

permissions: {}

jobs:
  describe:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/pr-description.yml@main
    permissions:
      contents: read
      pull-requests: write
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

### Create the token

Generate a one-year token tied to your Claude subscription, then store it as a
repository secret:

```sh
claude setup-token
gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo <owner>/<repo>
```

Without the secret, the job prints a warning and leaves the description alone.

### Choose the model

The model is chosen in one place: the default of the `model` input in
`.github/workflows/pr-description.yml`. Change it there to switch every caller at
once. A caller can still override it:

```yaml
jobs:
  describe:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/pr-description.yml@main
    with:
      model: sonnet
```

`model` takes a Claude Code alias (`opus`, `sonnet`, `haiku`, `fable`) or a full
model name.

### Use it in all your repositories

Everything is configured here, in `pr-description.yml`: the model, the effort, the
language, the prompt and the Claude Code version. Each repository needs only the two
things GitHub cannot share between the repositories of a personal account:

1. The caller file from [Usage](#usage), as `.github/workflows/pr-description.yml`.
2. The `CLAUDE_CODE_OAUTH_TOKEN` secret. Only an organization can share one secret
   between repositories, so set it on each repository in one loop, and run the loop
   again when the token expires after a year:

```sh
claude setup-token                # prints the token
read -rs CLAUDE_CODE_OAUTH_TOKEN  # paste it: it is not echoed
for repo in repo-a repo-b repo-c; do
  printf '%s' "$CLAUDE_CODE_OAUTH_TOKEN" | gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo "<owner>/$repo"
done
unset CLAUDE_CODE_OAUTH_TOKEN
```

The ref in the caller decides when a change made here reaches a repository. A
caller on `@main` picks it up at once. A caller pinned to a tag or a commit SHA
gets it only when the pin is bumped, by Renovate or by hand. Do not pin `@v0`:
releases move only the `v0.<minor>` aliases, so `v0` no longer follows them.

### Pull request template

The generated block always has the same shape: `## Summary` and `## Changes`,
then `## Breaking changes` and `## Notes for reviewers` when they apply. Put the
block in your pull request template where those sections belong, with the parts a
person writes below it: the workflow then fills the template instead of stacking
a second description on top of it.

```markdown
<!-- pr-description:start -->
## Summary

## Changes

-
<!-- pr-description:end -->

## Related issues

## How to test

## Checklist
```

A pull request template in the `.github` repository of an account or an
organization applies to every repository that has none of its own. The section
headings stay in English whatever `language` says, so they always match the
template.

## Inputs

| Input            | Type   | Default                     | Description                                                                     |
| ---------------- | ------ | --------------------------- | ------------------------------------------------------------------------------- |
| `model`          | string | set in `pr-description.yml` | Claude model that writes the description                                        |
| `effort`         | string | `medium`                    | Claude Code effort level (`low` to `max`); empty for Claude Code's default      |
| `language`       | string | `English`                   | Language of the text; the section headings stay in English                      |
| `max-diff-bytes` | number | `100000`                    | Size cap of the diff sent to Claude; the commit list and diffstat stay complete |
| `runner`         | string | `'"ubuntu-latest"'`         | Runner labels as JSON: Linux x64 or arm64 with glibc, curl, git, jq, python3    |

## Secrets

| Secret                    | Required | Description                                                    |
| ------------------------- | -------- | -------------------------------------------------------------- |
| `CLAUDE_CODE_OAUTH_TOKEN` | no       | Token from `claude setup-token`; without it the job only warns |

## Behaviour

1. Runs only for `pull_request` events on branches of the repository itself,
   opened by a person: fork pull requests get no secrets, and bot pull requests
   (Renovate, release-please) keep their own descriptions.
2. Collects the title, the commit messages, the diffstat and the diff. Lockfiles
   and minified or source-map files stay out of the diff, and a diff over
   `max-diff-bytes` is cut (Claude is told).
3. Installs the pinned Claude Code CLI with
   [`setup-claude-code`](../actions/setup-claude-code.md) and runs it headless,
   with no tool, from empty working and configuration directories: nothing in the
   checked-out repository (hooks, MCP servers, `CLAUDE.md`, settings) loads.
4. Writes the result into the managed block with the
   [`pr-description` action](../actions/pr-description.md): in place when the body
   has the block, as a pull request template can, or on top of the body otherwise.
   Text outside the block is kept; edits inside it are overwritten on the next push.

## Notes

- Each run counts against your plan's usage limits. A newer push cancels the run
  in progress.
- The token is tied to the subscription of the person who ran
  `claude setup-token`: keep it in your own repositories, not in a secret shared
  with other people.
- Anthropic's terms reserve subscription sign-in for Claude Code and its other
  native applications, and ask developers building on the Agent SDK to use an API
  key. This workflow runs the unmodified Claude Code CLI with a token from
  `claude setup-token`, the documented way to use a subscription in CI.
- A model released after the pinned Claude Code version may need a newer one:
  bump it in `setup-claude-code`.
- If the repository squash-merges with the pull request description as the commit
  message, the two HTML comments end up in that message.
