/**
 * GitHub API client and issue CRUD operations
 */

import {
  GhIssue,
  GhLabel,
  GhLabelFull,
  GhPR,
  GhFetchOptions,
  GhFileContent,
  GhRef,
} from './types.js';

const token = process.env.GITHUB_TOKEN;
const [owner, repoName] = (process.env.GITHUB_REPOSITORY || '').split('/');
export const repo = `${owner}/${repoName}`;

// ── GitHub API ────────────────────────────────────────────────────────────────

export async function ghFetch<T = unknown>(
  path: string,
  options: GhFetchOptions = {},
): Promise<T> {
  const method = options.method ?? 'GET';
  const url = `https://api.github.com${path}`;
  const headers: Record<string, string> = {
    Authorization: `Bearer ${token}`,
    Accept: 'application/vnd.github.v3+json',
  };

  const fetchOptions: RequestInit = {
    method,
    headers,
  };

  if (options.body) {
    fetchOptions.body = JSON.stringify(options.body);
    headers['Content-Type'] = 'application/json';
  }

  const res = await fetch(url, fetchOptions);
  if (!res.ok) {
    const text = await res.text();
    const error = new Error(`GitHub API error: ${res.status} ${res.statusText}\n${text}`);
    (error as any).statusCode = res.status;
    throw error;
  }

  return res.json() as Promise<T>;
}

// ── Issue CRUD ────────────────────────────────────────────────────────────────

export async function createIssue(
  title: string,
  body: string,
  labels: string[] = [],
  assignees: string[] = [],
): Promise<number> {
  const issue = await ghFetch<GhIssue>(`/repos/${owner}/${repoName}/issues`, {
    method: 'POST',
    body: { title, body, labels, assignees },
  });
  return issue.number;
}

export async function updateIssue(
  number: number,
  updates: Partial<{ title: string; body: string; state: string; labels: string[]; assignees: string[] }>,
): Promise<void> {
  await ghFetch(`/repos/${owner}/${repoName}/issues/${number}`, {
    method: 'PATCH',
    body: updates,
  });
}

export async function getIssue(number: number): Promise<GhIssue> {
  return ghFetch<GhIssue>(`/repos/${owner}/${repoName}/issues/${number}`);
}

export async function fetchAllIssues(): Promise<{
  byTitle: Map<string, GhIssue>;
  byNumber: Map<number, GhIssue>;
}> {
  const byTitle = new Map<string, GhIssue>();
  const byNumber = new Map<number, GhIssue>();

  let page = 1;
  let hasMore = true;

  while (hasMore) {
    const issues = await ghFetch<GhIssue[]>(`/repos/${owner}/${repoName}/issues?state=all&per_page=100&page=${page}`);

    if (issues.length === 0) {
      hasMore = false;
      break;
    }

    for (const issue of issues) {
      byTitle.set(issue.title, issue);
      byNumber.set(issue.number, issue);
    }

    page++;
  }

  return { byTitle, byNumber };
}

// ── Labels ────────────────────────────────────────────────────────────────────

export async function createLabel(name: string, color: string, description: string): Promise<GhLabelFull> {
  return ghFetch<GhLabelFull>(`/repos/${owner}/${repoName}/labels`, {
    method: 'POST',
    body: { name, color: color.replace('#', ''), description },
  });
}

export async function updateLabel(
  oldName: string,
  newName: string,
  color: string,
  description: string,
): Promise<GhLabelFull> {
  return ghFetch<GhLabelFull>(`/repos/${owner}/${repoName}/labels/${encodeURIComponent(oldName)}`, {
    method: 'PATCH',
    body: { new_name: newName, color: color.replace('#', ''), description },
  });
}

// ── Git refs ───────────────────────────────────────────────────────────────────

export async function getRefSha(ref: string): Promise<string> {
  try {
    const response = await ghFetch<GhRef>(`/repos/${owner}/${repoName}/git/refs/heads/${ref}`);
    return response.object.sha;
  } catch {
    return '';
  }
}

export async function createRef(ref: string, sha: string): Promise<void> {
  await ghFetch(`/repos/${owner}/${repoName}/git/refs`, {
    method: 'POST',
    body: { ref: `refs/heads/${ref}`, sha },
  });
}

export async function updateRef(ref: string, sha: string): Promise<void> {
  await ghFetch(`/repos/${owner}/${repoName}/git/refs/heads/${ref}`, {
    method: 'PATCH',
    body: { sha, force: true },
  });
}

// ── PR ─────────────────────────────────────────────────────────────────────────

export async function createPR(
  head: string,
  base: string,
  title: string,
  body: string,
): Promise<GhPR> {
  return ghFetch<GhPR>(`/repos/${owner}/${repoName}/pulls`, {
    method: 'POST',
    body: { head, base, title, body },
  });
}

export async function searchPRs(query: string): Promise<{ items: GhPR[] }> {
  return ghFetch<{ items: GhPR[] }>(`/search/issues?q=${encodeURIComponent(query)}`);
}
