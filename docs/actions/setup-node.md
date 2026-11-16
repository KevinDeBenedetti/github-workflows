---
title: Action — setup-node
---

# Action — setup-node

Installs Node.js and the correct package manager (**pnpm**, **bun** or **npm**), restoring the
appropriate dependency cache. Auto-detects the package manager from the lockfile.

## Usage

```yaml
steps:
  - uses: actions/checkout@v7

  - uses: KevinDeBenedetti/github-workflows/.github/actions/setup-node@main
    with:
      node-version: '24'
```

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `node-version` | string | `'24'` | Node.js version to install |
| `working-directory` | string | `'.'` | Directory to look for lockfile and run install |
| `package-manager` | string | `auto` | `pnpm` \| `bun` \| `npm` \| `auto` — auto-detects from lockfile |
| `pnpm-version` | string | `''` | pnpm version. Empty → the `packageManager` field of `package.json` (working directory, then repo root), else a pinned release (bumped by Renovate) |
| `bun-version` | string | pinned | Bun version installed when the package manager resolves to bun |
| `framework` | string | `auto` | `next` \| `nuxt` \| `vite` \| `auto` — auto-detects from the config files (`next.config.*`, `nuxt.config.*`, otherwise `vite`); only sets the `framework` and `build-output` outputs |
| `install` | boolean | `true` | Run install after setup |
| `cache` | boolean | `true` | Restore and save the dependency cache. `'false'` skips it, for a job that installs nothing (the Node.js audit of [security.yml](../workflows/security.md)) |

## Outputs

| Output | Description |
|---|---|
| `package-manager` | Resolved package manager (`pnpm`, `bun` or `npm`) |
| `lockfile` | Path of the lockfile the package manager reads (the working directory's, else the repository root's for a workspace member), relative to the repository root — hash it with `hashFiles` to key a cache of your own on the same dependency set |
| `run-command` | Command that runs a `package.json` script: `pnpm`, `npm run` or `bun run` (word-split it, then add the script name) |
| `audit-command` | Command that audits the lockfile at the high level, e.g. `pnpm audit --audit-level=high` |
| `framework` | Resolved framework (`next`, `nuxt` or `vite`) |
| `build-output` | The framework's build directory, relative to the working directory (`.next`, `.output` or `dist`) |
| `cache-hit` | Whether the package cache was restored |

## Steps

1. Resolve package manager from the nearest lockfile — `working-directory` first, then the repository root, so workspace members work (`bun.lockb` / `bun.lock` → bun, `package-lock.json` → npm, otherwise → pnpm)
2. Setup pnpm, bun or npm (with Node.js)
3. Restore cache (pnpm store, `~/.bun/install/cache`, or `~/.npm` via setup-node), keyed on the hash of the resolved lockfile — the repository root's for a workspace member, so a monorepo app's cache follows its dependency set instead of sharing one never-refreshed entry. Skipped with `cache: 'false'`
4. Install dependencies (`pnpm install --frozen-lockfile`, `bun install --frozen-lockfile` or `npm ci`, the latter run where `package-lock.json` lives)

Step 1 also resolves the framework (`next.config.*` → `next`, `nuxt.config.*` → `nuxt`, otherwise `vite`, unless `framework` forces one) and its build directory.

## Notes

- `install: 'false'` skips the install step — useful when you only need the toolchain and want to restore a build cache before installing.
- Use the `run-command` and `audit-command` outputs to run a script or an audit with the resolved package manager; `package-manager` is there for anything else that depends on it.
- pnpm version: when `package.json` declares `"packageManager": "pnpm@x.y.z"`, leave `pnpm-version` empty — pnpm/action-setup fails with *Multiple versions of pnpm specified* when both are set.
- Yarn is not supported.
- The package manager, lockfile, framework and commands are resolved by `resolve.sh`, next to the action: callers read the outputs instead of branching on the package manager again.
