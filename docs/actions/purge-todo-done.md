# Action — purge-todo-done

A repo-agnostic `prepare-commit-msg` Git hook that keeps `TODO.md` lean by
**flushing completed tasks at commit time**. When `TODO.md` is part of a commit,
it strips every checked item (`- [x] …`) from the **✅ Fait** (Done) section and
re-stages the file — the record of what was done lives in git history and the
commit message instead of piling up in the tracker. The `## ✅ Fait` heading is
kept; only its `- [x]` lines are removed.

It runs at the `prepare-commit-msg` stage (not `pre-commit`) on purpose: that
stage does **not** trigger the framework's "files were modified by this hook"
abort, so the purge lands in the **same commit, in one action** — no aborted
first commit, no second `git add`. If a particular git flow doesn't pick up the
re-stage, it degrades gracefully to leaving `TODO.md` modified in the working
tree. It is **fail-open**: it never blocks a commit.

## Usage

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/KevinDeBenedetti/github-workflows
    rev: main # or a release tag
    hooks:
      - id: purge-todo-done
```

Install the `prepare-commit-msg` hook type once per clone (the default
`pre-commit` install does not wire it up):

```bash
prek install -t prepare-commit-msg
# or, with pre-commit:
pre-commit install --hook-type prepare-commit-msg
```

It pairs naturally with [`ai-commit-msg`](ai-commit-msg.md): list `ai-commit-msg`
first so the generated message still "sees" the completed tasks in the staged
diff before `purge-todo-done` strips them.

## Inputs

_None_ (it reads the staged `TODO.md` directly). Behaviour is tuned via
environment variables.

## Environment variables

| Variable             | Default    | Description                                                       |
| -------------------- | ---------- | ----------------------------------------------------------------- |
| `TODO_PURGE_NO`      | `0`        | Set to `1` to disable the hook entirely (instant no-op).          |
| `TODO_PURGE_FILE`    | `TODO.md`  | Path to the tracker file to purge.                                |
| `TODO_PURGE_HEADING` | `Fait`     | Substring identifying the "Done" heading (matched on `## …` lines). |

## Notes

- **No-op conditions** (never blocks the commit): `TODO.md` not present, `TODO.md`
  not staged in this commit, the commit is a merge/squash, the Done section has no
  checked items, or any internal error.
- Only acts when `TODO.md` is **staged** — it will never smuggle an unrelated
  `TODO.md` edit into your commit.
- Only `- [x]` lines under the Done heading are removed; unchecked tasks, other
  sections, and the heading itself are left untouched.
- Completed tasks are not lost: they remain in git history at the commit where the
  work landed (and typically in that commit's message).
