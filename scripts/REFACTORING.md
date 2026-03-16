# Scripts Refactoring - Module Documentation

## Overview

The monolithic `sync-todo.ts` (757 lines) has been refactored into 9 focused, maintainable modules. Each module is **max 240 lines** with clear separation of concerns.

### Module Structure

```
scripts/
├── sync-todo.ts       (59 lines)  - Entry point and mode routing
├── types.ts           (122 lines) - Domain types and mappings
├── github.ts          (173 lines) - GitHub API client
├── files.ts           (24 lines)  - File I/O for TODO.yml
├── git.ts             (116 lines) - Git operations (branches, commits, PRs)
├── labels.ts          (80 lines)  - Label sync logic
├── issues.ts          (239 lines) - Issue sync (push/pull modes)
├── comments.ts        (53 lines)  - Issue comment helpers
└── formatters.ts      (58 lines)  - PR body formatting
```

**Total refactored code:** ~924 lines (vs 757 in monolithic version)  
**Modularity overhead:** ~167 lines of imports and exports (net improvement in maintainability)

---

## Module Descriptions

### 1. **sync-todo.ts** (Entry Point - 59 lines)

Minimal entry point that routes to the appropriate mode handler.

```typescript
// Usage: bun run sync-todo.ts <push|pull|labels>
switch (mode) {
  case 'push': push().catch(...)
  case 'pull': pull().catch(...)
  case 'labels': syncLabels().catch(...)
}
```

**Responsibility:** Mode dispatch only

---

### 2. **types.ts** (Domain Types - 122 lines)

All TypeScript types, interfaces, and domain-specific mappings.

**Exports:**
- Domain types: `TodoEntry`, `TodoFile`, `LabelDef`, `LabelsFile`
- GitHub API types: `GhIssue`, `GhPR`, `GhLabel`, etc.
- Mappings: `typeLabels`, `statusLabels`, `priorityLabels`

**Why separate:** Centralized type definitions enable easy schema changes. Label mappings are co-located with types for clarity.

---

### 3. **github.ts** (GitHub API Client - 173 lines)

Low-level GitHub API abstraction layer.

**Key functions:**
- `ghFetch()` - Generic API client with error handling
- `createIssue()`, `updateIssue()`, `getIssue()`, `fetchAllIssues()`
- `createLabel()`, `updateLabel()`
- `createRef()`, `updateRef()`, `getRefSha()`
- `createPR()`, `searchPRs()`

**Why separate:** Isolates GitHub API complexity. Easy to swap with GraphQL or mock for testing.

---

### 4. **files.ts** (File I/O - 24 lines)

Minimal file operations for reading/writing `TODO.yml`.

**Exports:**
- `readTodo()` - Parse YAML file
- `writeTodo()` - Write YAML file

**Why separate:** Tiny module, but centralizes file path logic and YAML handling.

---

### 5. **git.ts** (Git & PR Operations - 116 lines)

Handles git branch operations and pull request management.

**Key functions:**
- `createBranch()`, `branchExists()`, `resetBranchToMain()`
- `pushTodoToBranch()` - Commit TODO.yml to branch
- `findOpenSyncPR()` - Find existing sync PR
- `createPRWithTodo()` - Create or skip PR creation

**Why separate:** Git operations are orthogonal to GitHub API and domain logic. Easier to refactor branch strategies.

---

### 6. **labels.ts** (Label Sync - 80 lines)

Label synchronization logic and label-to-entry mapping.

**Key functions:**
- `ensureLabel()` - Create or update a single label
- `ensureLabels()` - Ensure all built-in labels exist
- `labelsForEntry()` - Map TodoEntry to GitHub labels
- `syncLabels()` - Main entry point for labels mode

**Why separate:** Label logic is distinct from issue sync. Custom labels in `labels.yml` have separate sync flow.

---

### 7. **issues.ts** (Issue Sync - 239 lines)

Core business logic: push mode (TODO.yml → Issues) and pull mode (Issues → TODO.yml).

**Key functions:**
- `detectChanges()` - Compare TodoEntry vs GhIssue
- `resolveIssue()` - Find or recover issue by ID or title
- `push()` - Main push mode handler
- `pull()` - Main pull mode handler

**Why largest:** Contains core sync logic and state reconciliation. Still under 300 lines.

---

### 8. **comments.ts** (Comment Helpers - 53 lines)

Issue comment composition and formatting.

**Exports:**
- `addComment()` - Post comment to issue
- `createdComment()` - Message for newly created issues
- `closedComment()` - Message for closed issues
- `changesComment()` - Message for updates

**Why separate:** Centralizes comment formatting. Easy to internationalize or change tone.

---

### 9. **formatters.ts** (PR Body Formatting - 58 lines)

Pull request body formatting for sync PRs.

**Exports:**
- `formatPushPRBody()` - Format push mode summary
- `formatPullPRBody()` - Format pull mode summary

**Why separate:** Presentation logic isolated from business logic. Easy to test and change formatting.

---

## Dependency Graph

```
sync-todo.ts
  ├─> issues.ts
  │    ├─> github.ts ─> types.ts
  │    ├─> files.ts ─> types.ts
  │    ├─> git.ts ─> github.ts
  │    ├─> labels.ts
  │    ├─> comments.ts ─> types.ts
  │    └─> formatters.ts ─> types.ts
  └─> labels.ts
      ├─> github.ts ─> types.ts
      └─> types.ts
```

**Key properties:**
- Minimal coupling
- Unidirectional dependencies
- `types.ts` is a leaf (no exports depend on code modules)
- `github.ts` is isolated (no domain logic imports)

---

## Testing

Each module can be tested independently:

```bash
# Test label sync
bun run sync-todo.ts labels

# Test push mode
GITHUB_TOKEN=... GITHUB_REPOSITORY=owner/repo \
  bun run sync-todo.ts push

# Test pull mode
GITHUB_TOKEN=... GITHUB_REPOSITORY=owner/repo ISSUE_NUMBER=42 \
  bun run sync-todo.ts pull
```

---

## Maintenance Benefits

### 1. **Readability**
- Each file is <250 lines, fits on screen
- Single responsibility = easier to understand
- Clear module boundaries

### 2. **Testability**
- Easy to mock `github.ts` for unit tests
- Can test `issues.ts` logic independently
- Comment and formatter functions are pure

### 3. **Extensibility**
- Add new modes by creating new module + updating `sync-todo.ts`
- Swap GitHub API for GraphQL by editing `github.ts` only
- Add new issue comment types in `comments.ts` only

### 4. **Debugging**
- Error traces point to specific modules
- Easy to add debug logging per module
- Reduced context switching between functions

---

## Migration Checklist

- [x] Extract types to `types.ts`
- [x] Create GitHub API module `github.ts`
- [x] Create file I/O module `files.ts`
- [x] Create git operations module `git.ts`
- [x] Create label sync module `labels.ts`
- [x] Create issue sync module `issues.ts`
- [x] Create comment helpers module `comments.ts`
- [x] Create formatter module `formatters.ts`
- [x] Create entry point `sync-todo.ts`
- [x] Test all three modes (push/pull/labels)
- [ ] Remove backup file `sync-todo.ts.backup`
- [ ] Update CI/CD if needed

---

## Future Improvements

1. **Unit tests** - Jest/Vitest configuration
2. **Integration tests** - Mock GitHub API responses
3. **Logging** - Add debug logging per module
4. **Error handling** - Typed error classes
5. **GraphQL migration** - Replace REST API with GraphQL
6. **CLI improvements** - Add flags like `--dry-run`, `--verbose`
