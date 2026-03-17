# TODO.yml ↔ GitHub Issues Sync

Bidirectional sync between a `TODO.yml` file in each repository and GitHub Issues.  
`TODO.yml` is the **single source of truth** — all issue management happens through this file.

---

## Overview

```
TODO.yml  ──push mode──▶  GitHub Issues
TODO.yml  ◀──pull mode──  GitHub Issues
labels.yml ──labels mode─▶ Repo labels
```

| Mode | Trigger | Direction |
|------|---------|-----------|
| `push` | Push to `TODO.yml` on `main` | TODO.yml → Issues |
| `pull` | GitHub issue event | Issue → TODO.yml |
| `labels` | Push to `labels.yml` | labels.yml → repo labels |

All three modes run via a single TypeScript script (`scripts/sync-todo.ts`, executed with [Bun](https://bun.sh)).  
Changes to `TODO.yml` are **never committed directly to `main`** — they open (or update) a single pull request on the `sync/todo` branch for your review.

---

## Setup

### 1. Add the caller workflow

Create `.github/workflows/todo-sync.yml` in your repo:

```yaml
name: TODO sync

on:
  push:
    branches: [main]
    paths: ['TODO.yml']
  issues:
    types: [labeled, unlabeled, closed, reopened, edited, assigned, unassigned]
  workflow_dispatch:

jobs:
  sync:
    permissions:
      contents: write
      issues: write
      pull-requests: write
    uses: KevinDeBenedetti/github-workflows/.github/workflows/todo-sync.yml@main
    with:
      issue-number: ${{ github.event.issue.number || 0 }}
    secrets: inherit
```

### 2. Add a `TODO.yml` at the repo root

```yaml
issues:
  - github_id: ~
    type: feat
    title: "Add dark mode support"
    status: backlog
    priority: medium
    assignees: [KevinDeBenedetti]
    body: |
      ## Goal
      ...

      ## Acceptance criteria
      - [ ] ...
```

### 3. Configure `PAT_TOKEN`

A fine-grained PAT is required with the following permissions:

| Permission | Access | Why |
|---|---|---|
| `contents` | Read & Write | Commit `TODO.yml` changes via Contents API |
| `issues` | Read & Write | Create, update, close issues |
| `pull-requests` | Read & Write | Open and comment on the `sync/todo` PR |

Store it as a repository or organisation secret named `PAT_TOKEN`.

---

## `TODO.yml` reference

### File structure

```yaml
issues:
  - github_id: 42          # auto-filled on first push — never edit manually
    type: feat              # see Type reference
    title: "Verb + context" # required — start with a verb
    status: backlog         # see Status reference
    priority: high          # see Priority reference
    assignees:
      - KevinDeBenedetti
    body: |                 # optional — markdown body for the issue
      ## Goal
      ...
      ## Acceptance criteria
      - [ ] ...
```

### Fields

| Field | Required | Description |
|---|---|---|
| `github_id` | Yes | GitHub issue number. Set to `~` (null) for new entries. Written back automatically after creation. **Never edit manually.** |
| `type` | Yes | Category of work — determines the type label. |
| `title` | Yes | Issue title. Must start with a verb. |
| `status` | Yes | Current status — determines the status label and open/closed state. |
| `priority` | Yes | Urgency level — determines the priority label. |
| `assignees` | Yes | List of GitHub usernames. Can be empty (`[]`). |
| `body` | No | Markdown content for the issue body. |

### Type reference

| Value | GitHub label | Color |
|---|---|---|
| `feat` | `feature` | ![#0075ca](https://via.placeholder.com/12/0075ca/0075ca.png) `#0075ca` |
| `fix` | `bug` | ![#d73a4a](https://via.placeholder.com/12/d73a4a/d73a4a.png) `#d73a4a` |
| `refactor` | `refactor` | ![#e4e669](https://via.placeholder.com/12/e4e669/e4e669.png) `#e4e669` |
| `chore` | `chore` | ![#ededed](https://via.placeholder.com/12/ededed/ededed.png) `#ededed` |
| `doc` | `documentation` | ![#0052cc](https://via.placeholder.com/12/0052cc/0052cc.png) `#0052cc` |
| `security` | `security` | ![#b60205](https://via.placeholder.com/12/b60205/b60205.png) `#b60205` |

### Status reference

| Value | GitHub label | Issue state | Effect on sync |
|---|---|---|---|
| `backlog` | `status: backlog` | open | — |
| `in-progress` | `status: in-progress` | open | — |
| `to-review` | `status: to-review` | open | — |
| `done` | `status: done` | **closed** | Issue closed + **entry deleted** from `TODO.yml` |

> ⚠️ Setting `status: done` is the only way to remove an entry. The sync closes the issue on GitHub and removes the entry from `TODO.yml` via the sync PR.

### Priority reference

| Value | GitHub label | Color |
|---|---|---|
| `high` | `priority: high` | `#b60205` (red) |
| `medium` | `priority: medium` | `#ff7619` (orange) |
| `low` | `priority: low` | `#e4e669` (yellow) |

---

## How push mode works

Triggered by a push to `TODO.yml` on `main` (or `workflow_dispatch`).

### Step-by-step

```
1. ensureLabels()         — create/skip all 13 labels in the target repo
2. readTodo()             — parse TODO.yml
3. fetchAllIssues()       — paginate ALL issues (open + closed) into two maps:
                              byTitle  → normalised lowercase title
                              byNumber → github_id
4. For each entry:
   a. resolveIssue()      — find the matching GitHub issue (see below)
   b. Apply changes       — create / update / close the issue
   c. Comment on issue    — post a sync comment with the action taken
5. Remove done entries    — filter entries with status: done from data.issues
6. If anything changed:
   writeTodo()            — serialise updated TODO.yml to disk
   createPRWithTodo()     — open or update the sync/todo PR
```

### Issue resolution (`resolveIssue`)

The sync verifies entries by **both `github_id` and title** to handle edge cases:

| Situation | Behaviour |
|---|---|
| `github_id` set, issue found by id | ✅ Use it. Cross-check title — warn if title also matches a different issue. |
| `github_id` set, not found by id, found by title | ⚠️ Warn + recover using the title match. Update `github_id`. |
| `github_id` set, found nowhere | ⚠️ Warn + recreate the issue. |
| `github_id: ~`, found by title | ↩️ Recover — link to existing issue, write back `github_id`. |
| `github_id: ~`, not found anywhere | ✅ Create new issue. |

This makes the sync **idempotent**: re-running after a partial failure never creates duplicate issues.

### Change detection

Before updating an issue, `detectChanges()` diffs all fields between the TODO entry and the live GitHub issue. A `changesComment` is posted only when at least one field differs:

| Tracked field | Source |
|---|---|
| `title` | Direct comparison |
| `body` | Trimmed content comparison (truncated in comment) |
| `type` | Type label present on issue |
| `status` | `status: *` label present on issue |
| `priority` | `priority: *` label present on issue |
| `assignees` | Sorted list of login names |
| `state` | `open` / `closed` derived from `status: done` |

### Issue comments

Each issue receives a comment on every meaningful sync action:

| Action | Comment |
|---|---|
| First sync (created or recovered) | 🤖 Table with type / status / priority |
| Fields changed | 🔄 Diff table showing each changed field |
| Closed via `status: done` | 🔒 Closed notice |

---

## How pull mode works

Triggered by a GitHub issue event (labeled, unlabeled, closed, reopened, edited, assigned).  
Reads the issue state and reflects any changes back into `TODO.yml`.

### Step-by-step

```
1. getIssue(ISSUE_NUMBER)  — fetch current issue state
2. Find entry by github_id in TODO.yml
3. Snapshot before values  — title, status, priority, assignees
4. Apply GitHub → TODO.yml:
   - issue.state === 'closed'  → entry.status = 'done'
   - status: * label            → entry.status
   - priority: * label          → entry.priority
   - issue.title                → entry.title
   - issue.assignees            → entry.assignees
5. If status became 'done'     → remove entry from data.issues
6. Compute diff (before vs after)
7. If no changes               → skip (no PR)
8. writeTodo() + createPRWithTodo()
```

> Pull mode **skips** silently when no changes are detected. This prevents spurious PRs when push mode's issue updates (labels, close) re-trigger the issue event.

---

## The `sync/todo` PR

All TODO.yml changes (new `github_id` values, status syncs, removed entries) are collected into a **single persistent pull request** on the `sync/todo` branch. You review and merge at your own pace.

### Branch lifecycle

```
PR merged / no open PR   →  reset sync/todo to main → push file → open new PR
PR already open          →  push updated file → add comment to existing PR
Branch does not exist    →  create from main → push file → open new PR
```

### PR content

- **PR description**: summary table of all changes in the triggering run.
- **PR comments**: one comment per subsequent run while the PR stays open, each with its own change table.

> Commits to `sync/todo` use the message `chore: sync TODO.yml [skip ci]`.  
> GitHub recognises `[skip ci]` natively — merging the PR will **not** re-trigger `todo-sync.yml`.

---

## Labels mode

Syncs label definitions from `KevinDeBenedetti/.github/labels.yml` to the target repo.  
Uses `POST` (create) with a `422` fallback to `PATCH` (update) — fully idempotent.

### Caller workflow

```yaml
on:
  push:
    branches: [main]
    paths: ['labels.yml']
  workflow_dispatch:

jobs:
  sync-labels:
    permissions:
      issues: write
    uses: KevinDeBenedetti/github-workflows/.github/workflows/label-sync.yml@main
    secrets:
      token: ${{ secrets.PAT_TOKEN }}
```

### `labels.yml` format

```yaml
labels:
  - name: feature
    color: '0075ca'
    description: New feature or improvement
  - name: status: backlog
    color: 'c2e0c6'
    description: Not yet started
```

---

## Reusable workflows reference

### `todo-yml-push.yml`

| | |
|---|---|
| **Trigger** | `workflow_call` |
| **Permissions** | `contents: write`, `issues: write`, `pull-requests: write` |
| **Secret** | `token` — PAT (falls back to `github.token`) |
| **Script mode** | `push` |

Steps: checkout caller repo → sparse-checkout `scripts/` from `github-workflows` → `bun install` → `bun run sync-todo.ts push`

### `todo-yml-pull.yml`

| | |
|---|---|
| **Trigger** | `workflow_call` |
| **Permissions** | `contents: write`, `issues: read`, `pull-requests: write` |
| **Input** | `issue-number` (number, required) |
| **Secret** | `token` — PAT (required) |
| **Script mode** | `pull` |

### `label-sync.yml`

| | |
|---|---|
| **Trigger** | `workflow_call` |
| **Permissions** | `issues: write` |
| **Input** | `labels-path` (string, default: `labels.yml`) |
| **Secret** | `token` — PAT |
| **Script mode** | `labels` |

---

## Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `GITHUB_TOKEN` | Yes | — | PAT or `github.token`. Used for all API calls. |
| `GITHUB_REPOSITORY` | Yes | — | `owner/repo` format — set automatically by Actions. |
| `ISSUE_NUMBER` | Pull mode only | — | Issue number from `github.event.issue.number`. |
| `TODO_PATH` | No | `TODO.yml` | Path to the TODO file relative to repo root. |
| `LABELS_PATH` | No | `labels.yml` | Path to the labels file (labels mode only). |
| `DEFAULT_BRANCH` | No | `main` | Override the base branch for PR creation. Falls back to `GITHUB_REF_NAME`. |

---

## Extending the system

### Adding a new issue type

1. **`scripts/sync-todo.ts`** — add to `TYPE_LABEL_MAP`:
   ```typescript
   mytype: 'my-label-name',
   ```

2. **`KevinDeBenedetti/.github/labels.yml`** — add the label definition:
   ```yaml
   - name: my-label-name
     color: 'aabbcc'
     description: Description of the type
   ```
   Push to `labels.yml` to trigger `label-sync.yml` across all repos.

3. **`dotfiles/config/vscode/settings.json`** — add to `todo-tree.general.tags`:
   ```json
   "MYTYPE"
   ```

### Adding a new status

1. Add to `STATUS_LABEL_MAP` in `sync-todo.ts`.
2. The reverse `LABEL_STATUS_MAP` is derived automatically — no extra step.
3. Add the label to `labels.yml`.

---

## Local testing

```bash
# From the github-workflows repo root
cd scripts
bun install

# Push mode against any repo
GITHUB_TOKEN=<your-pat> \
GITHUB_REPOSITORY=KevinDeBenedetti/my-repo \
TODO_PATH=../my-repo/TODO.yml \
bun run sync-todo.ts push

# Pull mode (simulate an issue event)
GITHUB_TOKEN=<your-pat> \
GITHUB_REPOSITORY=KevinDeBenedetti/my-repo \
TODO_PATH=../my-repo/TODO.yml \
ISSUE_NUMBER=5 \
bun run sync-todo.ts pull

# Labels mode
GITHUB_TOKEN=<your-pat> \
GITHUB_REPOSITORY=KevinDeBenedetti/my-repo \
LABELS_PATH=../../.github/labels.yml \
bun run sync-todo.ts labels
```

Use a `.env` file at `scripts/.env` for local token storage (already in `.gitignore`):

```env
PAT_TOKEN=github_pat_...
```

Then source it:

```bash
GITHUB_TOKEN=$(grep PAT_TOKEN .env | cut -d= -f2) \
GITHUB_REPOSITORY=KevinDeBenedetti/my-repo \
bun run sync-todo.ts push
```

---

## Full example `TODO.yml`

```yaml
issues:
  - github_id: 12
    type: feat
    title: "Add dark mode support"
    status: in-progress
    priority: high
    assignees:
      - KevinDeBenedetti
    body: |
      ## Goal
      Allow users to toggle between light and dark themes.

      ## Acceptance criteria
      - [ ] Toggle button in header
      - [ ] Preference persisted in localStorage
      - [ ] Respects system `prefers-color-scheme`

  - github_id: ~
    type: fix
    title: "Fix login redirect loop on expired session"
    status: backlog
    priority: high
    assignees: []
    body: |
      ## Goal
      Prevent infinite redirect when the session cookie is expired.

      ## Acceptance criteria
      - [ ] Redirect to /login with a `?next=` param
      - [ ] Session expiry shows a toast notification
```

---

## Architecture overview

```
KevinDeBenedetti/
├── .github/
│   ├── labels.yml              ← single source of truth for all labels
│   └── .github/workflows/
│       ├── label-sync.yml      ← caller: push labels.yml → repo labels
│       └── todo-sync.yml       ← caller: TODO.yml ↔ Issues
│
├── github-workflows/
│   ├── TODO.yml
│   ├── scripts/
│   │   ├── sync-todo.ts        ← entry point (59 lines)
│   │   ├── types.ts            ← domain types (122 lines)
│   │   ├── github.ts           ← API client (173 lines)
│   │   ├── files.ts            ← file I/O (24 lines)
│   │   ├── git.ts              ← git operations (116 lines)
│   │   ├── labels.ts           ← label sync (80 lines)
│   │   ├── issues.ts           ← push/pull logic (239 lines)
│   │   ├── comments.ts         ← comment helpers (53 lines)
│   │   ├── formatters.ts       ← formatting (58 lines)
│   │   ├── package.json        ← js-yaml dependency
│   │   └── tsconfig.json
│   └── .github/workflows/
│       ├── todo-sync.yml       ← reusable: push + pull mode (recommended)
│       ├── todo-yml-push.yml   ← reusable: push mode only
│       ├── todo-yml-pull.yml   ← reusable: pull mode only
│       └── label-sync.yml      ← reusable: labels mode
│
└── <any-repo>/
    ├── TODO.yml                ← managed here
    └── .github/workflows/
        └── todo-sync.yml       ← caller: thin wrapper over todo-sync.yml
```

### Module structure (refactored v2)

The `scripts/` directory has been refactored from a monolithic 757-line file into 9 focused modules, each with a single responsibility:

| Module | Lines | Responsibility |
|--------|-------|---|
| `sync-todo.ts` | 59 | Entry point & mode dispatch |
| `types.ts` | 122 | Domain types, interfaces & mappings |
| `github.ts` | 167 | GitHub REST API client abstraction |
| `files.ts` | 24 | YAML file I/O operations |
| `git.ts` | 120 | Git branches, commits & PR operations |
| `labels.ts` | 80 | Label sync logic & mapping |
| `issues.ts` | 239 | Push/pull mode logic & state reconciliation |
| `comments.ts` | 53 | Issue comment composition |
| `formatters.ts` | 58 | PR body formatting |

**Benefits of modular design:**
- Improved readability (largest module ~240 lines)
- Easier testing (unit test each module independently)
- Better maintainability (clear separation of concerns)
- Simpler debugging (error traces point to specific modules)
- Extensible (add new modes without modifying existing code)

## Code Quality Tooling

The scripts now include automated linting, formatting, and type checking:

- **Oxlint**: Rust-based linter (100x faster than ESLint), runs in ~6ms
- **TypeScript**: Strict mode type checking, enforces strong type safety
- **Auto-fix**: Most issues are automatically fixed with `bun run lint`

Development workflow:
```bash
cd scripts/
bun install           # One-time setup
bun run lint          # Linting with auto-fixes
bun run typecheck     # Type checking
```
