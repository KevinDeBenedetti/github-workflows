/**
 * Domain types, interfaces, and label mappings for TODO.yml ↔ GitHub Issues sync
 */

// ── Domain types ──────────────────────────────────────────────────────────────

export type IssueType = 'feat' | 'fix' | 'refactor' | 'chore' | 'doc' | 'security';
export type IssueStatus = 'backlog' | 'in-progress' | 'to-review' | 'done';
export type Priority = 'high' | 'medium' | 'low';

export interface TodoEntry {
  github_id: number | null;
  type: IssueType;
  title: string;
  status: IssueStatus;
  priority: Priority;
  assignees: string[];
  body?: string;
}

export interface TodoFile {
  issues: TodoEntry[];
}

export interface LabelDef {
  name: string;
  color: string;
  description: string;
}

export interface LabelsFile {
  labels: LabelDef[];
}

// ── GitHub API response shapes (partial) ─────────────────────────────────────

export interface GhLabel {
  name: string;
}

export interface GhAssignee {
  login: string;
}

export interface GhLabelFull {
  id: number;
  name: string;
  color: string;
  description: string | null;
}

export interface GhIssue {
  number: number;
  title: string;
  body: string | null;
  state: 'open' | 'closed';
  labels: GhLabel[];
  assignees: GhAssignee[];
}

export interface GhFileContent {
  sha: string;
}

export interface GhRef {
  object: { sha: string };
}

export interface GhPR {
  number: number;
  html_url: string;
}

export interface SyncLogEntry {
  issueNumber: number;
  title: string;
  action: 'created' | 'recovered' | 'linked' | 'updated' | 'unchanged' | 'closed';
  changes?: IssueChanges;
}

export interface IssueChanges {
  title?: [string, string];
  body?: [string, string];
  type?: [string, string];
  status?: [string, string];
  priority?: [string, string];
  assignees?: [string, string];
  state?: ['open' | 'closed', 'open' | 'closed'];
}

export interface GhFetchOptions {
  method?: 'GET' | 'POST' | 'PATCH' | 'PUT' | 'DELETE';
  body?: Record<string, unknown>;
}

// ── Type → label mapping ──────────────────────────────────────────────────────

export const typeLabels: Record<IssueType, LabelDef> = {
  feat: { name: 'type/feat', color: '#0366D6', description: 'feature request' },
  fix: { name: 'type/fix', color: '#D73A49', description: 'bug fix' },
  refactor: { name: 'type/refactor', color: '#6F42C1', description: 'code refactoring' },
  chore: { name: 'type/chore', color: '#8B6B47', description: 'chore' },
  doc: { name: 'type/doc', color: '#F0883E', description: 'documentation' },
  security: { name: 'type/security', color: '#FBCA04', description: 'security' },
};

// ── Status → label mapping ────────────────────────────────────────────────────

export const statusLabels: Record<IssueStatus, LabelDef> = {
  backlog: { name: 'status/backlog', color: '#CCCCCC', description: 'backlog' },
  'in-progress': { name: 'status/in-progress', color: '#0366D6', description: 'in progress' },
  'to-review': { name: 'status/to-review', color: '#FFA500', description: 'to review' },
  done: { name: 'status/done', color: '#28A745', description: 'done' },
};

// ── Priority → label mapping ──────────────────────────────────────────────────

export const priorityLabels: Record<Priority, LabelDef> = {
  high: { name: 'priority/high', color: '#D73A49', description: 'high priority' },
  medium: { name: 'priority/medium', color: '#FFA500', description: 'medium priority' },
  low: { name: 'priority/low', color: '#CCCCCC', description: 'low priority' },
};
