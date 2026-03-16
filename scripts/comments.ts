/**
 * Issue comment helpers and formatting
 */

import { ghFetch } from './github.js';
import { TodoEntry, IssueChanges } from './types.js';

const [owner, repoName] = (process.env.GITHUB_REPOSITORY || '').split('/');

export async function addComment(number: number, body: string): Promise<void> {
  await ghFetch(`/repos/${owner}/${repoName}/issues/${number}/comments`, {
    method: 'POST',
    body: { body },
  });
}

export function createdComment(entry: TodoEntry): string {
  const content = entry.body ? entry.body.trim() : '(no description)';
  return `**Synced from TODO.yml**\n\n${content}`;
}

export function closedComment(): string {
  return '✅ Closed by TODO.yml (status: done)';
}

export function changesComment(entry: TodoEntry, changes: IssueChanges): string {
  const lines: string[] = ['**Synced from TODO.yml:**'];

  if (changes.title) {
    lines.push(`- **Title:** ${changes.title[0]} → ${changes.title[1]}`);
  }
  if (changes.status) {
    lines.push(`- **Status:** ${changes.status[0]} → ${changes.status[1]}`);
  }
  if (changes.priority) {
    lines.push(`- **Priority:** ${changes.priority[0]} → ${changes.priority[1]}`);
  }
  if (changes.type) {
    lines.push(`- **Type:** ${changes.type[0]} → ${changes.type[1]}`);
  }
  if (changes.assignees) {
    lines.push(`- **Assignees:** ${changes.assignees[0]} → ${changes.assignees[1]}`);
  }
  if (changes.body) {
    lines.push(`- **Description:** Updated`);
  }

  if (entry.body) {
    lines.push(`\n${entry.body}`);
  }

  return lines.join('\n');
}
