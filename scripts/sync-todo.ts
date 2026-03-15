#!/usr/bin/env bun
/**
 * sync-todo.ts — bidirectional sync between TODO.yml and GitHub Issues
 *
 * push mode   TODO.yml → GitHub Issues
 *   - New entries (github_id: null) → create issue, write back id
 *   - Existing entries              → update title / body / labels / assignees
 *   - status: done                  → close issue
 *
 * pull mode   GitHub Issue event → TODO.yml
 *   - Sync state, title, assignees from the issue back into TODO.yml
 *
 * labels mode  labels.yml → GitHub repo labels  (upsert: create or update)
 *
 * Env vars:
 *   GITHUB_TOKEN       PAT (PAT_TOKEN) or built-in GITHUB_TOKEN
 *   GITHUB_REPOSITORY  owner/repo  (e.g. KevinDeBenedetti/dotfiles)
 *   ISSUE_NUMBER       issue number — pull mode only
 *   TODO_PATH          path to TODO.yml   (default: TODO.yml)
 *   LABELS_PATH        path to labels.yml (default: labels.yml)
 *
 * Local testing:
 *   GITHUB_TOKEN=$(grep PAT_TOKEN .env | cut -d= -f2) \
 *   GITHUB_REPOSITORY=KevinDeBenedetti/<repo> \
 *   bun run scripts/sync-todo.ts push
 */

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { execSync } from 'node:child_process';
import yaml from 'js-yaml';

// ── Domain types ──────────────────────────────────────────────────────────────

type IssueType   = 'feat' | 'fix' | 'refactor' | 'chore' | 'doc' | 'security';
type IssueStatus = 'backlog' | 'in-progress' | 'to-review' | 'done';
type Priority    = 'high' | 'medium' | 'low';

interface TodoEntry {
  id:        string;
  github_id: number | null;
  type:      IssueType;
  title:     string;
  status:    IssueStatus;
  priority:  Priority;
  assignees: string[];
  body?:     string;
}

interface TodoFile {
  issues: TodoEntry[];
}

interface LabelsFile {
  labels: LabelDef[];
}

// ── GitHub API response shapes (partial) ─────────────────────────────────────

interface GhLabel    { name: string }
interface GhAssignee { login: string }
interface GhLabelFull { id: number; name: string; color: string; description: string | null }

interface GhIssue {
  number:    number;
  title:     string;
  body:      string | null;
  state:     'open' | 'closed';
  labels:    GhLabel[];
  assignees: GhAssignee[];
}

interface GhFetchOptions {
  method?: 'GET' | 'POST' | 'PATCH' | 'DELETE';
  body?:   Record<string, unknown>;
}

// ── Type → label mapping ──────────────────────────────────────────────────────
// When adding a new type:
//   1. Add entry here
//   2. Add label to KevinDeBenedetti/.github/labels.yml
//   3. Add tag to dotfiles/config/vscode/settings.json → todo-tree.general.tags
const TYPE_LABEL_MAP: Record<IssueType, string> = {
  feat:     'feature',
  fix:      'bug',
  refactor: 'refactor',
  chore:    'chore',
  doc:      'documentation',
  security: 'security',
};

// ── Status → label mapping ────────────────────────────────────────────────────
const STATUS_LABEL_MAP: Record<IssueStatus, string> = {
  'backlog':     'status: backlog',
  'in-progress': 'status: in-progress',
  'to-review':   'status: to-review',
  'done':        'status: done',
};

// Reverse map: label name → status (for pull mode)
const LABEL_STATUS_MAP: Record<string, IssueStatus> = Object.fromEntries(
  Object.entries(STATUS_LABEL_MAP).map(([s, l]) => [l, s as IssueStatus]),
);

// ── Priority → label mapping ──────────────────────────────────────────────────
const PRIORITY_LABEL_MAP: Record<Priority, string> = {
  high:   'priority: high',
  medium: 'priority: medium',
  low:    'priority: low',
};

// Reverse map: label name → priority (for pull mode)
const LABEL_PRIORITY_MAP: Record<string, Priority> = Object.fromEntries(
  Object.entries(PRIORITY_LABEL_MAP).map(([p, l]) => [l, p as Priority]),
);

// Label definitions — auto-created in target repo on first push
interface LabelDef { name: string; color: string; description: string }
const LABEL_DEFS: LabelDef[] = [
  { name: 'feature',           color: '0075ca', description: 'New feature or improvement' },
  { name: 'bug',               color: 'd73a4a', description: "Something isn't working" },
  { name: 'refactor',          color: 'e4e669', description: 'Code refactoring without functional change' },
  { name: 'chore',             color: 'ededed', description: 'Maintenance, tooling, or dependencies' },
  { name: 'documentation',     color: '0052cc', description: 'Improvements or additions to documentation' },
  { name: 'security',          color: 'b60205', description: 'Security fix or improvement' },
  { name: 'status: backlog',     color: 'c2e0c6', description: 'Not yet started' },
  { name: 'status: in-progress', color: 'fef2c0', description: 'Actively being worked on' },
  { name: 'status: to-review',   color: 'fbca04', description: 'Ready for review' },
  { name: 'status: done',        color: '0e8a16', description: 'Completed' },
  { name: 'priority: high',      color: 'b60205', description: 'Must be addressed urgently' },
  { name: 'priority: medium',    color: 'ff7619', description: 'Important but not urgent' },
  { name: 'priority: low',       color: 'e4e669', description: 'Nice to have' },
];

// ── GitHub API ────────────────────────────────────────────────────────────────

const token = process.env.GITHUB_TOKEN;
const repo  = process.env.GITHUB_REPOSITORY;

if (!token || !repo) {
  console.error('Missing required env vars: GITHUB_TOKEN, GITHUB_REPOSITORY');
  process.exit(1);
}

const [owner, repoName] = repo.split('/') as [string, string];

async function ghFetch<T = unknown>(path: string, options: GhFetchOptions = {}): Promise<T> {
  const res = await fetch(`https://api.github.com${path}`, {
    method: options.method ?? 'GET',
    headers: {
      Authorization:          `Bearer ${token}`,
      Accept:                 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'Content-Type':         'application/json',
    },
    body: options.body ? JSON.stringify(options.body) : undefined,
  });

  if (res.status === 204) return null as T;
  const json = await res.json() as T;
  if (!res.ok) {
    throw new Error(`GitHub API ${options.method ?? 'GET'} ${path} → ${res.status}: ${JSON.stringify(json)}`);
  }
  return json;
}

// ── Labels ────────────────────────────────────────────────────────────────────

async function ensureLabel(def: LabelDef): Promise<void> {
  try {
    await ghFetch(`/repos/${owner}/${repoName}/labels`, { method: 'POST', body: { ...def } });
    console.log(`  label created: ${def.name}`);
  } catch (err) {
    // 422 = already exists — safe to ignore
    if (!(err instanceof Error) || !err.message.includes('422')) throw err;
  }
}

async function ensureLabels(): Promise<void> {
  console.log('Ensuring labels exist…');
  for (const def of LABEL_DEFS) await ensureLabel(def);
}

function labelsForEntry(entry: TodoEntry): string[] {
  const labels: string[] = [];
  const typeLabel     = TYPE_LABEL_MAP[entry.type];
  const statusLabel   = STATUS_LABEL_MAP[entry.status];
  const priorityLabel = entry.priority ? PRIORITY_LABEL_MAP[entry.priority] : undefined;
  if (typeLabel)     labels.push(typeLabel);
  if (statusLabel)   labels.push(statusLabel);
  if (priorityLabel) labels.push(priorityLabel);
  return labels;
}

// ── Issue CRUD ────────────────────────────────────────────────────────────────

async function createIssue(
  fields: { title: string; body: string; labels: string[]; assignees: string[] },
): Promise<GhIssue> {
  return ghFetch<GhIssue>(`/repos/${owner}/${repoName}/issues`, {
    method: 'POST',
    body: { ...fields },
  });
}

async function updateIssue(
  number: number,
  fields: Partial<{ title: string; body: string; labels: string[]; assignees: string[]; state: 'open' | 'closed' }>,
): Promise<GhIssue> {
  return ghFetch<GhIssue>(`/repos/${owner}/${repoName}/issues/${number}`, {
    method: 'PATCH',
    body: { ...fields },
  });
}

async function getIssue(number: number): Promise<GhIssue> {
  return ghFetch<GhIssue>(`/repos/${owner}/${repoName}/issues/${number}`);
}

// Fetch all repo issues (open + closed) and index them by normalised title
async function fetchIssuesByTitle(): Promise<Map<string, GhIssue>> {
  const map   = new Map<string, GhIssue>();
  let   page  = 1;
  while (true) {
    const batch = await ghFetch<GhIssue[]>(
      `/repos/${owner}/${repoName}/issues?state=all&per_page=100&page=${page}`,
    );
    if (!batch.length) break;
    for (const issue of batch) map.set(issue.title.trim().toLowerCase(), issue);
    if (batch.length < 100) break;
    page++;
  }
  return map;
}

// ── TODO.yml helpers ──────────────────────────────────────────────────────────

const TODO_PATH = process.env.TODO_PATH ?? 'TODO.yml';

function readTodo(): TodoFile {
  if (!existsSync(TODO_PATH)) {
    console.error(`${TODO_PATH} not found`);
    process.exit(1);
  }
  return yaml.load(readFileSync(TODO_PATH, 'utf8')) as TodoFile;
}

function writeTodo(data: TodoFile): void {
  writeFileSync(TODO_PATH, yaml.dump(data, { indent: 2, lineWidth: -1, noRefs: true }), 'utf8');
}

function commitTodo(): void {
  execSync('git config user.name  "github-actions[bot]"');
  execSync('git config user.email "github-actions[bot]@users.noreply.github.com"');
  execSync(`git add ${TODO_PATH}`);

  const staged = execSync('git diff --cached --name-only').toString().trim();
  if (!staged) { console.log('Nothing to commit.'); return; }

  execSync('git commit -m "chore: sync github_id in TODO.yml [skip ci]"');
  execSync('git push');
  console.log('Committed and pushed TODO.yml updates.');
}

// ── Push mode: TODO.yml → GitHub Issues ──────────────────────────────────────

async function push(): Promise<void> {
  await ensureLabels();

  const data   = readTodo();
  const issues = data.issues ?? [];
  let   dirty  = false;

  // Pre-fetch all existing issues once — used to detect duplicates (idempotency)
  const existingByTitle = await fetchIssuesByTitle();

  for (const entry of issues) {
    const labels    = labelsForEntry(entry);
    const assignees = entry.assignees ?? [];
    const body      = (entry.body ?? '').trim();
    const state     = entry.status === 'done' ? 'closed' : 'open' as const;

    if (!entry.github_id) {
      // ── Idempotency: reuse existing issue with same title if found ────────
      const existing = existingByTitle.get(entry.title.trim().toLowerCase());
      if (existing) {
        console.log(`Recovered existing issue #${existing.number} for "${entry.title}"`);
        entry.github_id = existing.number;
        dirty = true;
        await updateIssue(existing.number, { title: entry.title, body, labels, assignees, state });
      } else {
        // ── Create new issue ────────────────────────────────────────────────
        console.log(`Creating issue: "${entry.title}"`);
        const issue = await createIssue({ title: entry.title, body, labels, assignees });
        entry.github_id = issue.number;
        dirty = true;
        console.log(`  → #${issue.number}`);
        if (state === 'closed') await updateIssue(issue.number, { state: 'closed' });
      }
    } else {
      // ── Sync existing issue ───────────────────────────────────────────────
      console.log(`Syncing issue #${entry.github_id}: "${entry.title}"`);
      await updateIssue(entry.github_id, { title: entry.title, body, labels, assignees, state });
    }
  }

  if (dirty) { writeTodo(data); commitTodo(); }
}

// ── Pull mode: GitHub Issue → TODO.yml ───────────────────────────────────────

async function pull(): Promise<void> {
  const issueNumber = parseInt(process.env.ISSUE_NUMBER ?? '', 10);
  if (!issueNumber) {
    console.error('ISSUE_NUMBER env var is required for pull mode');
    process.exit(1);
  }

  const issue  = await getIssue(issueNumber);
  const data   = readTodo();
  const entry  = data.issues?.find(e => e.github_id === issueNumber);

  if (!entry) {
    console.log(`No TODO.yml entry found for issue #${issueNumber} — skipping`);
    return;
  }

  // Status: closed issue → done; otherwise read from status label
  if (issue.state === 'closed') {
    entry.status = 'done';
  } else {
    const labelNames  = issue.labels.map(l => l.name);
    const statusLabel = labelNames.find(n => n in LABEL_STATUS_MAP);
    if (statusLabel) {
      entry.status = LABEL_STATUS_MAP[statusLabel]!;
    } else if (entry.status === 'done') {
      entry.status = 'backlog'; // issue was reopened with no status label
    }
    // Priority: sync back if a priority label is present on the issue
    const priorityLabel = labelNames.find(n => n in LABEL_PRIORITY_MAP);
    if (priorityLabel) entry.priority = LABEL_PRIORITY_MAP[priorityLabel]!;
  }

  // Title and assignees synced back for consistency
  entry.title     = issue.title;
  entry.assignees = issue.assignees.map(a => a.login);

  console.log(`Updated TODO.yml for issue #${issueNumber}: status=${entry.status}`);
  writeTodo(data);
  commitTodo();
}

// ── Labels mode: labels.yml → GitHub repo labels ─────────────────────────────

async function syncLabels(): Promise<void> {
  const labelsPath = process.env.LABELS_PATH ?? 'labels.yml';
  if (!existsSync(labelsPath)) {
    console.error(`${labelsPath} not found`);
    process.exit(1);
  }

  const file = yaml.load(readFileSync(labelsPath, 'utf8')) as LabelsFile;
  const defs = file.labels ?? [];
  console.log(`Syncing ${defs.length} labels to ${repo}…`);

  for (const def of defs) {
    try {
      // Try create first
      await ghFetch<GhLabelFull>(`/repos/${owner}/${repoName}/labels`, {
        method: 'POST',
        body: { name: def.name, color: def.color.replace('#', ''), description: def.description },
      });
      console.log(`  created: ${def.name}`);
    } catch (err) {
      if (!(err instanceof Error) || !err.message.includes('422')) throw err;
      // 422 = already exists → update instead
      await ghFetch<GhLabelFull>(
        `/repos/${owner}/${repoName}/labels/${encodeURIComponent(def.name)}`,
        {
          method: 'PATCH',
          body: { new_name: def.name, color: def.color.replace('#', ''), description: def.description },
        },
      );
      console.log(`  updated: ${def.name}`);
    }
  }

  console.log('Label sync complete.');
}

// ── Main ──────────────────────────────────────────────────────────────────────

const mode = process.argv[2];
if      (mode === 'push')   push().catch(err => { console.error((err as Error).message); process.exit(1); });
else if (mode === 'pull')   pull().catch(err => { console.error((err as Error).message); process.exit(1); });
else if (mode === 'labels') syncLabels().catch(err => { console.error((err as Error).message); process.exit(1); });
else {
  console.error('Usage: bun run sync-todo.ts push|pull|labels');
  process.exit(1);
}
