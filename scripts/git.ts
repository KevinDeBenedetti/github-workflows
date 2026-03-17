/**
 * Git operations: branches, commits, and pull requests
 */

import {
  createRef,
  createPR,
  getRefSha,
  updateRef,
  searchPRs,
  ghFetch,
  repo,
} from './github.js';

const [owner, repoName] = repo.split('/');

// ── Branch operations ──────────────────────────────────────────────────────────

export async function branchExists(name: string): Promise<string | null> {
  try {
    const sha = await getRefSha(name);
    return sha || null;
  } catch {
    return null;
  }
}

export async function createBranch(name: string, sha: string): Promise<void> {
  await createRef(name, sha);
}

export async function resetBranchToMain(name: string): Promise<void> {
  const mainSha = await getRefSha('main');
  await updateRef(name, mainSha);
}

// ── Commit operations ──────────────────────────────────────────────────────────

export async function pushTodoToBranch(branch: string): Promise<void> {
  const todoPath = 'TODO.yml';

  // Get the file SHA
  const fileRes = await ghFetch<{ sha: string; content: string }>(
    `/repos/${owner}/${repoName}/contents/${todoPath}?ref=main`,
  );
  const baseSha = fileRes.sha;

  // Read current TODO.yml from disk
  const { readFileSync } = await import('node:fs');
  const content = readFileSync(todoPath, 'utf8');
  const encoded = Buffer.from(content).toString('base64');

  // Commit to branch
  await ghFetch(`/repos/${owner}/${repoName}/contents/${todoPath}`, {
    method: 'PUT',
    body: {
      branch,
      message: 'chore(sync): update TODO.yml',
      content: encoded,
      sha: baseSha,
    },
  });
}

// ── PR operations ──────────────────────────────────────────────────────────────

export async function findOpenSyncPR(): Promise<{ number: number; html_url: string } | null> {
  try {
    const result = await searchPRs(
      `repo:${repo} is:open author:github-actions head:sync/todo-yml-push-main`,
    );

    if (result.items && result.items.length > 0) {
      const pr = result.items[0];
      if (pr && pr.number && pr.html_url) {
        return { number: pr.number, html_url: pr.html_url };
      }
    }
  } catch {
    // Silently fail if search doesn't work
  }

  return null;
}

export async function createPRWithTodo(prTitle: string, prBody: string): Promise<void> {
  const branchName = 'sync/todo-yml-push-main';
  const mainSha = await getRefSha('main');

  // Try to find existing PR
  const existingPR = await findOpenSyncPR();
  if (existingPR) {
    console.log(`  existing PR #${existingPR.number}`);
    return;
  }

  // Reset or create branch
  const exists = await branchExists(branchName);
  if (exists) {
    await resetBranchToMain(branchName);
  } else {
    await createBranch(branchName, mainSha);
  }

  // Push TODO.yml to branch
  await pushTodoToBranch(branchName);

  // Create PR
  try {
    const pr = await createPR(branchName, 'main', prTitle, prBody);
    console.log(`  created PR #${pr.number}`);
  } catch (err) {
    if (!(err instanceof Error) || !err.message.includes('422')) throw err;
    // 422 = PR already exists (race condition)
    console.log(`  PR already exists`);
  }
}
