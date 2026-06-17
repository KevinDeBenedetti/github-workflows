# Action — ai-commit-msg

A repo-agnostic `prepare-commit-msg` Git hook that pre-fills your commit message
from the **staged diff** using the `claude` CLI (headless `claude -p`). On a plain
`git commit`, it asks Claude for a [Conventional Commits](https://www.conventionalcommits.org)
message (title + bullet body) built from `git diff --cached` and drops it into the
editor — you review and edit before the commit completes.

It is **fail-open by design**: it never blocks a commit. It is a no-op when a
message is already present (`-m`, `-t` template, amend, merge, squash), nothing is
staged, the `claude` CLI is missing/offline/disabled, or anything errors.

## Usage

Unlike the other entries here, this is a **pre-commit hook**, not a CI composite
action. Add it to your repo's [prek](https://prek.j178.dev) / `pre-commit` config,
pointing at this repository as a hook source:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/KevinDeBenedetti/github-workflows
    rev: main # or a release tag for reproducibility
    hooks:
      - id: ai-commit-msg
```

The hook runs at the `prepare-commit-msg` stage, which is **not** installed by the
default `pre-commit` install. Install that hook type once per clone:

```bash
prek install -t prepare-commit-msg
# or, with pre-commit:
pre-commit install --hook-type prepare-commit-msg
```

## Inputs

_None_ (it reads the staged diff directly). Behaviour is tuned via environment
variables.

## Environment variables

| Variable             | Default  | Description                                                        |
| -------------------- | -------- | ------------------------------------------------------------------ |
| `AI_COMMIT_NO_AI`      | `0`      | Set to `1` to disable the hook entirely (instant no-op).            |
| `AI_COMMIT_MODEL`      | `sonnet` | Model passed to `claude -p --model`.                                |
| `AI_COMMIT_TIMEOUT`    | `60`     | Seconds before giving up (requires `timeout`/`gtimeout`).           |
| `AI_COMMIT_MAX_CHARS`  | `12000`  | Caps the staged-diff payload sent to Claude (latency/cost guard).   |
| `AI_COMMIT_CLAUDE_BIN` | _(auto)_ | Explicit path to the `claude` binary. Set this if auto-resolution fails. |

## Notes

- **No-op conditions** (never blocks the commit): message already present, no
  staged changes, `claude` not on `PATH`, or any internal error.
- Output is sanitized — stray code-fence lines and leading blank lines are
  stripped — and prepended above the existing commit-message template, so your
  comment block (`# Please enter the commit message…`) is preserved.
- The diff is sent leading with `git diff --cached --stat` for high-level context,
  then the full diff truncated to `AI_COMMIT_MAX_CHARS`.
- Requires the [`claude` CLI](https://docs.claude.com/en/docs/claude-code).
  Without it (or if it cannot be located) the hook silently does nothing.

## Using it from a GUI Git client (VS Code, etc.)

If the message generates from a terminal `git commit` but **not** when you click
the commit button in VS Code, Tower, or another GUI, the cause is almost always
`PATH`: GUI apps don't source your `~/.zshrc`/`~/.bashrc`, so `claude` isn't found.

This hook works around that by also probing common install locations (Homebrew,
npm/bun/pnpm globals, `~/.local/bin`, `~/.claude/local`). If your `claude` lives
elsewhere, point the hook at it explicitly via `AI_COMMIT_CLAUDE_BIN` — e.g. in a
repo-local Git config or your shell profile:

```bash
git config hooks.ai-commit-bin "$(command -v claude)"   # informational
export AI_COMMIT_CLAUDE_BIN="$(command -v claude)"        # what the hook reads
```

Also make sure the `prepare-commit-msg` hook type is actually installed
(`prek install -t prepare-commit-msg`) — the default `pre-commit` install does
**not** wire up `prepare-commit-msg`, so the hook never runs otherwise.

## Smoke-testing the live generation path

`tests/ai-commit-msg.bats` covers the hook's logic with a fake `claude` (no
network). To confirm a **real** `claude -p` call returns a usable message, run the
manual smoke test — it stages a sample diff, drives the hook against the live CLI,
and fails if nothing valid comes back (no commit is created):

```bash
tests/smoke/ai-commit-msg-smoke.sh
```

It is intentionally excluded from CI, which has neither network nor `claude`
credentials.
