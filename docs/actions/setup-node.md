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
| `pnpm-version` | string | `''` | pnpm version. Empty → the `packageManager` field of `package.json` (working directory, then repo root), else latest |
| `install` | boolean | `true` | Run install after setup |

## Outputs

| Output | Description |
|---|---|
| `package-manager` | Resolved package manager (`pnpm`, `bun` or `npm`) |
| `cache-hit` | Whether the package cache was restored |

## Steps

1. Resolve package manager from the nearest lockfile — `working-directory` first, then the repository root, so workspace members work (`bun.lockb` / `bun.lock` → bun, `package-lock.json` → npm, otherwise → pnpm)
2. Setup pnpm, bun or npm (with Node.js)
3. Restore cache (pnpm store, `~/.bun/install/cache`, or `~/.npm` via setup-node)
4. Install dependencies (`pnpm install --frozen-lockfile`, `bun install --frozen-lockfile` or `npm ci`, the latter run where `package-lock.json` lives)

## Notes

- `install: 'false'` skips the install step — useful when you only need the toolchain and want to restore a build cache before installing.
- The `package-manager` output can be used in subsequent steps to conditionally run `pnpm`, `bun` or `npm` commands.
- pnpm version: when `package.json` declares `"packageManager": "pnpm@x.y.z"`, leave `pnpm-version` empty — pnpm/action-setup fails with *Multiple versions of pnpm specified* when both are set.
- Yarn is not supported.
