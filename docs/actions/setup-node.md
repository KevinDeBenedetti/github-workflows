# Action — setup-node

Installs Node.js and the correct package manager (**pnpm** or **bun**), restoring the
appropriate dependency cache. Auto-detects the package manager from the lockfile.

## Usage

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: KevinDeBenedetti/github-workflows/.github/actions/setup-node@main
    with:
      node-version: '20'
```

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `node-version` | string | `'20'` | Node.js version to install |
| `working-directory` | string | `'.'` | Directory to look for lockfile and run install |
| `package-manager` | string | `auto` | `pnpm` \| `bun` \| `auto` — auto-detects from lockfile |
| `install` | boolean | `true` | Run install after setup |

## Outputs

| Output | Description |
|---|---|
| `package-manager` | Resolved package manager (`pnpm` or `bun`) |
| `cache-hit` | Whether the package cache was restored |

## Steps

1. Resolve package manager (`bun.lockb` / `bun.lock` → bun, otherwise → pnpm)
2. Setup pnpm **or** bun (with Node.js)
3. Restore cache (pnpm store or `~/.bun/install/cache`)
4. Install dependencies (`--frozen-lockfile`)

## Notes

- `install: 'false'` skips the install step — useful when you only need the toolchain and want to restore a build cache before installing.
- The `package-manager` output can be used in subsequent steps to conditionally run `pnpm` or `bun` commands.
