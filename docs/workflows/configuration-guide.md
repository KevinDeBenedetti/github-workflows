# Purge Workflows — Configuration Guide

This guide explains how to configure retention thresholds and understand the purge behaviors for workflow runs, deployments, and caches.

## Overview

The purge workflows help maintain repository hygiene by automatically removing old GitHub Actions artifacts. Three types of artifacts can be purged:

- **Workflow Runs**: Historical execution records of GitHub Actions workflows
- **Deployments**: Environment deployment history and records
- **Caches**: Build and dependency caches used by workflows

## Global Configuration

### `keep` — Items to Retain

Controls how many most-recent items to keep before deletion.

**Default:** `10`

**How it works:**
- Workflows runs are sorted newest-first (API default)
- The `keep` newest runs/deployments/caches are protected
- Anything older is eligible for deletion

**Recommended values:**

| Use Case | Value | Rationale |
|----------|-------|-----------|
| **Archive-heavy** (compliance, long audit trail) | 30–50 | Keep 1–2 months of history; useful if you need detailed historical records |
| **Standard** (most projects) | 10–20 | Recommended balance; keeps 1–3 weeks of runs at typical cadence |
| **Aggressive** (storage-optimized) | 3–5 | Keep only critical runs; suitable for high-volume CI |

**Example:** With `keep: 10` and 50 total workflow runs, the 10 newest are kept; 40 are deleted.

---

### `dry-run` — Preview Mode

When enabled, shows what would be deleted without actually deleting anything.

**Default:** `true` (safe by default)

**How it works:**
- `dry-run: true` → Log deletion candidates; don't delete
- `dry-run: false` → Actually delete items

**Recommendation:** Always run `dry-run: true` first to preview changes before setting `dry-run: false`.

---

## Workflow-Specific Configuration

### Purge — Workflow Runs

**File:** `.github/workflows/purge-workflow-runs.yml`

#### Inputs

| Input | Default | Purpose |
|-------|---------|---------|
| `keep` | `10` | Keep N most-recent runs per workflow |
| `workflow` | `""` | Filter to specific workflow (e.g., `ci-node.yml`). Empty = all workflows |
| `status` | `""` | Filter to specific status: `completed`, `failure`, `cancelled`, `skipped`. Empty = all |
| `dry-run` | `false` | Preview without deleting |

#### Examples

**Scenario 1: Clean up all workflows, keep 20 most recent**
```yaml
with:
  keep: 20
  dry-run: true
```

**Scenario 2: Delete failed runs older than 10 most-recent per workflow**
```yaml
with:
  keep: 10
  status: failure
  dry-run: false
```

**Scenario 3: Dry-run on specific workflow**
```yaml
with:
  workflow: ci-node.yml
  keep: 5
  dry-run: true
```

---

### Purge — Deployments

**File:** `.github/workflows/purge-deployments.yml`

#### Inputs

| Input | Default | Purpose |
|-------|---------|---------|
| `keep` | `10` | Keep N most-recent deployments per environment |
| `max-age-days` | `30` | Delete deployments older than N days (0 = no age limit) |
| `environment` | `""` | Filter to specific environment (e.g., `production`). Empty = all |
| `dry-run` | `false` | Preview without deleting |

#### How Deletion Works

Deployments must satisfy **both** conditions to be deleted:
1. Beyond the `keep` threshold (oldest in each environment)
2. **AND** older than `max-age-days`

This dual-filter prevents accidental deletion of recent items while respecting age policies.

#### Examples

**Scenario 1: Keep 10 most-recent per environment, no age limit**
```yaml
with:
  keep: 10
  max-age-days: 0  # No age filter, only count-based
  dry-run: true
```

**Scenario 2: Keep only last 5 deployments that are >30 days old**
```yaml
with:
  keep: 5
  max-age-days: 30
  dry-run: false
```

**Scenario 3: Clean production environment only**
```yaml
with:
  environment: production
  keep: 20
  max-age-days: 90
  dry-run: true
```

---

### Purge — Caches

**File:** `.github/workflows/purge-caches.yml`

#### Inputs

| Input | Default | Purpose |
|-------|---------|---------|
| `keep` | `10` | Keep N most-recently-used caches |
| `ref` | `""` | Filter to specific branch/ref (e.g., `refs/heads/main`). Empty = all |
| `dry-run` | `false` | Preview without deleting |

#### How Deletion Works

Caches are sorted by **last access time** (newest first). The `keep` most-recently-accessed caches are protected.

#### Examples

**Scenario 1: Keep 10 most-used caches across all branches**
```yaml
with:
  keep: 10
  dry-run: true
```

**Scenario 2: Clean caches on main branch only**
```yaml
with:
  ref: refs/heads/main
  keep: 5
  dry-run: false
```

**Scenario 3: Aggressive cache cleanup**
```yaml
with:
  keep: 3
  dry-run: true
```

---

## Orchestrator Configuration

**File:** `.github/workflows/maintenance.yml`

Triggers all three purge workflows (deployments, workflow runs, caches) with consistent settings.

### Inputs

| Input | Default | Purpose |
|-------|---------|---------|
| `keep` | `10` | Passed to all three purge workflows |
| `dry-run` | `true` | Preview without deleting |

### Using the Orchestrator

**Trigger manually from Actions:**
1. Go to [Maintenance](https://github.com/KevinDeBenedetti/github-workflows/actions/workflows/maintenance.yml)
2. Click **Run workflow**
3. Set `keep` and `dry-run`
4. Click **Run workflow**

**Example: Dry-run with aggressive cleanup**
```
keep: 5
dry-run: true ✓
filter-repo: (leave empty for all repos)
```

---

## Best Practices

### 1. Always Dry-run First

```yaml
# Step 1: Preview
dry-run: true
# Review run summary and reported deletions

# Step 2: If satisfied, execute
dry-run: false
```

### 2. Adjust by Workload

- **High-frequency CI** (many runs/day): Use `keep: 5–10`
- **Standard projects** (few runs/day): Use `keep: 10–20`
- **Low-volume projects**: Use `keep: 20–50` to preserve history

### 3. Separate Policies by Environment

```yaml
# Production: Conservative (keep more history for audit)
jobs:
  purge-prod:
    with:
      environment: production
      keep: 50
      max-age-days: 180

  # Staging: Standard (fewer deployments to track)
  purge-staging:
    with:
      environment: staging
      keep: 20
      max-age-days: 90
```

### 4. Monitor Usage

Check the JSON report artifact (`purge-report-json`) after each run to:
- Track deletion trends
- Understand storage impact
- Adjust thresholds based on actual usage

### 5. Schedule vs. Manual

- **Schedule** (weekly): Conservative settings; `keep: 10–20`, `dry-run: true` (preview only)
- **Manual**: Run `dry-run: false` when you're ready to execute, with your chosen thresholds

---

## Troubleshooting

### "Nothing to delete" despite old runs

Possible causes:
- `keep` value is higher than total items (e.g., `keep: 50` but only 20 runs exist)
- Items are within retention window (age or count)

**Fix:** Lower `keep` value or check total item count in step summary.

### Deployments not being deleted

Deployments require **both** conditions:
1. Beyond `keep` threshold
2. **AND** older than `max-age-days`

**Fix:** Ensure `max-age-days > 0` and items are old enough.

### Can't see what was deleted

1. Check the workflow run's **step summary** for immediate details
2. Download `purge-report-json` artifact for full historical record
3. Individual purge workflows (purge-runs, purge-deployments, purge-caches) show per-item logs

---

## See Also

- [Purge Reporting Guide](./purge-reporting-guide.md)
- [Purge Deployments Workflow](./purge-deployments.md)
- [Purge Workflow Runs Workflow](./purge-workflow-runs.md)
- [Purge Caches Workflow](./purge-caches.md)
