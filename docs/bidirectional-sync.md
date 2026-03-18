# Bidirectional TODO.yml ↔ GitHub Issues Sync

Simple, automatic synchronization between TODO.yml and GitHub Issues.

## How It Works

### Push → Issues (when TODO.yml changes)
1. Edit TODO.yml in the main branch and push
2. `todo-to-issues.yml` workflow triggers
3. For each entry:
   - If `github_id: null` → **create** new GitHub issue
   - If `github_id` exists → **update** the issue title and state
4. Issue numbers are written back to TODO.yml immediately

### Pull ← Issues (when issues change)
1. Open, edit, close, or reopen an issue on GitHub
2. `issues-to-todo.yml` workflow triggers  
3. **Creates new entry** in TODO.yml if needed or **updates existing one**
4. Opens a PR with the TODO.yml changes

## TODO.yml Schema

**That's it. Just 4 fields:**

```yaml
todos:
  - id: "FEAT-01"              # Your ID (e.g., FEAT-01, BUG-42, etc.)
    title: "Add dark mode"     # Short description
    github_id: null            # GitHub issue number (auto-filled)
    status: open               # open | in_progress | closed

  - id: "BUG-07"
    title: "Fix login crash"
    github_id: 57              # Links to issue #57
    status: closed
```

**Empty file:**
```yaml
todos: []
```

## Usage

### Add a new item to track
```yaml
- id: "FEAT-02"
  title: "Implement notifications"
  github_id: null
  status: open
```

Push this to main → workflow creates GitHub issue #42 (for example) → TODO.yml auto-updates to `github_id: 42`

### Change status
```yaml
- id: "FEAT-02"
  title: "Implement notifications"
  github_id: 42
  status: in_progress    # Changed from: open
```

Push → workflow updates issue #42 status

### Complete a task
```yaml
- id: "FEAT-02"
  title: "Implement notifications"
  github_id: 42
  status: closed         # Changed from: in_progress
```

Push → workflow closes issue #42

## Loop Prevention

Two safeguards prevent infinite loops:

1. **Push→Issues**: Skips commits with `[skip-todo-sync]` flag
2. **Issues→TODO**: Skips events from `github-actions[bot]`

When the workflow opens a PR, it uses `[skip-todo-sync]` in the commit message, so merging won't trigger the push workflow again.

## Manual Sync

Test before pushing:

```bash
cd scripts

# Test TODO→Issues
DRY_RUN=true GH_TOKEN=<your-token> REPO=owner/repo bun x tsx sync-todo-to-issues.ts

# Test Issue→TODO (example)
DRY_RUN=true \
  ISSUE_NUMBER=42 \
  ISSUE_TITLE="My issue" \
  ISSUE_STATE=open \
  bun x tsx sync-issue-to-todo.ts
```

Or use npm:
```bash
npm run sync-to-issues      # or: bun run sync-to-issues
npm run sync-from-issue     # or: bun run sync-from-issue
```

## Examples

### Simple workflow
```
1. Add to TODO.yml:
   - id: "FEAT-03"
     title: "Add export to CSV"
     github_id: null
     status: open

2. git push origin main

3. Workflow creates issue (e.g., #100)

4. TODO.yml auto-updates:
   - id: "FEAT-03"
     title: "Add export to CSV"
     github_id: 100          # ← Now linked
     status: open

5. You can now modify the issue on GitHub, and changes sync back to TODO.yml
```

### Issue-first workflow
```
1. Someone opens an issue on GitHub (#88: "Fix typos")

2. Workflow creates entry in TODO.yml:
   - id: "GH-88"
   title: "Fix typos"
   github_id: 88
   status: open

3. Workflow opens PR to merge this into main

4. You can edit the id/title in TODO.yml before merging
```

## Status Values

- `open` - In backlog, not started
- `in_progress` - Currently being worked on
- `closed` - Done or won't do

## Fields: Why So Simple?

- **id**: Your identifier (helps organize TODOs)
- **title**: One-line description
- **github_id**: The link to GitHub (null = not created yet)
- **status**: Current state

Everything else (labels, assignees, milestones) lives in GitHub Issues. This keeps TODO.yml lightweight and easy to edit.

## Troubleshooting

**"ISSUE_NUMBER must be a valid positive integer"**
- The environment variable is missing or invalid

**"GitHub API error (401): Bad credentials"**
- Your GH_TOKEN is missing or expired
- Generate a new token at https://github.com/settings/tokens

**Issue created but GitHub issue not synced to TODO.yml**
- Check if you created an entry that already existed
- The workflow runs on issue events; check Actions logs

**Workflow not triggering**
- For push→issues: Make sure you edited TODO.yml (other files won't trigger)
- For issues→todo: Make sure you didn't create the issue via the bot
- Check .github/workflows/todo-*.yml files exist and are enabled

## Files

```
.github/workflows/
  ├── todo-to-issues.yml      # Triggers on TODO.yml push
  └── issues-to-todo.yml      # Triggers on issue events

scripts/
  ├── types.ts                # Type definitions
  ├── todo-utils.ts           # File I/O helpers
  ├── sync-todo-to-issues.ts  # Push mode
  └── sync-issue-to-todo.ts   # Pull mode

TODO.yml                        # Your tracked items
```
