# Purge All Repos — Maintenance Orchestrator

Automatically triggers the `maintenance.yml` workflow (deployments + workflow runs + caches purge) across all your public and private repositories on a schedule. Safely defaults to `dry-run: true` so you can preview before actual deletion.

## How it works

1. Discovers all your repositories (public + private)
2. Filters by optional pattern
3. Checks each repo has `maintenance.yml`
4. Triggers `maintenance.yml` via `workflow_dispatch` with configurable inputs
5. Runs up to 3 repos in parallel to avoid rate limits

## Usage

### Automatic (weekly schedule)

Runs every **Sunday at 03:00 UTC** by default:

```yaml
on:
  schedule:
    - cron: '0 3 * * 0'  # Every Sunday at 03:00 UTC
```

### Manual trigger

Go to **Actions → Purge All Repos — Maintenance Orchestrator → Run workflow** and set:

- `keep` — number of deployments/runs/caches to retain (default: 10)
- `dry-run` — preview before deleting (default: **true** — safe!)
- `filter-repo` — optional pattern to target specific repos (e.g. `my-org/foo-*`)

## Inputs

| Input         | Type    | Default | Description                                                                  |
| ------------- | ------- | ------- | ---------------------------------------------------------------------------- |
| `keep`        | number  | `10`    | Number of most-recent items to keep per repo (deployments/runs/caches)       |
| `dry-run`     | boolean | `true`  | Preview what would be deleted without deleting (safe default)                |
| `filter-repo` | string  | `''`    | Filter repos by name pattern (e.g. `my-org/foo-*`). Empty = all repos       |

## Permissions

Requires a Personal Access Token (PAT) with:
- `repo` scope (access to public and private repos)
- `workflow` scope (ability to trigger workflows)

Set as repository secret `PURGE_PAT` and use in the caller (see below), or use `github.token` (default) if running in a repo you own with sufficient token permissions.

## Integration with caller workflows

To trigger this from another repo or organization-level automation:

```yaml
name: Weekly purge
on:
  schedule:
    - cron: '0 3 * * 0'
jobs:
  purge-all:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/purge-all-repos.yml@main
    secrets:
      token: ${{ secrets.PURGE_PAT }}  # Optional: use custom PAT instead of github.token
    with:
      keep: 10
      dry-run: true
```

## How to adopt

Each repo must have `.github/workflows/maintenance.yml` present. Copy from `examples/maintenance.yml`:

```bash
# In each of your repos:
mkdir -p .github/workflows
cp examples/maintenance.yml .github/workflows/
git add .github/workflows/maintenance.yml
git commit -m "chore: add maintenance workflow"
git push
```

Or use GitHub's [repository template](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-template-repository) feature to sync it automatically to all new repos.

## Workflow behavior

1. **Discovery phase** — lists all repos, optionally filters by pattern
2. **Dispatch phase** — triggers `maintenance.yml` on each repo with inputs, runs 3 repos in parallel
3. **Non-blocking** — if a repo fails or doesn't have `maintenance.yml`, the orchestrator continues (uses `continue-on-error`)
4. **Summary** — reports that workflows were triggered; check individual repo Actions tabs for detailed results

## Best practices

- **Start with dry-run** — first execution should have `dry-run: true` to preview what each repo would delete
- **Review before deletion** — check the job summaries in each repo's Actions tab to confirm safe deletions
- **Stagger large organizations** — if you have 100+ repos, increase `max-parallel` gradually or run filters
- **Backup critical deployments** — ensure you have external deployment records before auto-purging

## Troubleshooting

- **"No maintenance.yml found"** — that repo doesn't have the maintenance workflow yet; add it via `examples/maintenance.yml`
- **Rate limit errors** — GitHub API limits 3 concurrent workflow triggers per repo; the orchestrator respects this
- **Token permissions** — ensure your PAT has `repo` + `workflow` scopes

## Notes

- This orchestrator workflow lives in the central `github-workflows` repo
- Each target repo must have its own `maintenance.yml` for this to work
- Dry-run defaults to **true** for safety — uncheck only after reviewing what would be deleted
