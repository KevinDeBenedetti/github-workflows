# Action — detect-changes

Detects which subdirectories under `apps/` (or a custom directory) have changed since the
last commit, and outputs a JSON matrix for use in downstream matrix jobs.

## Usage

```yaml
jobs:
  detect:
    runs-on: ubuntu-latest
    outputs:
      changed-apps: ${{ steps.changes.outputs.changed-apps }}
      has-changes:  ${{ steps.changes.outputs.has-changes }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: KevinDeBenedetti/github-workflows/.github/actions/detect-changes@main
        id: changes
        with:
          apps-directory: apps

  build:
    needs: detect
    if: needs.detect.outputs.has-changes == 'true'
    strategy:
      matrix:
        app: ${{ fromJson(needs.detect.outputs.changed-apps) }}
    runs-on: ubuntu-latest
    steps:
      - run: echo "Building ${{ matrix.app }}"
```

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `apps-directory` | string | `apps` | Root directory containing app subdirectories |
| `base-ref` | string | `''` | Base git ref to compare against (auto-detected if empty) |

## Outputs

| Output | Description |
|---|---|
| `changed-apps` | JSON array of changed app names, e.g. `["api","web"]` |
| `has-changes` | `"true"` or `"false"` — whether any app changed |
| `changed-api` | `"true"` or `"false"` — whether `apps/api` changed |
| `changed-web` | `"true"` or `"false"` — whether `apps/web` changed |
| `changed-client` | `"true"` or `"false"` — whether `apps/client` changed |

## Base ref resolution

1. Uses `base-ref` input if provided
2. Falls back to `github.event.pull_request.base.sha` on pull requests
3. Falls back to `github.event.before` on push events
4. Falls back to `HEAD~1` if the before SHA is empty or all zeros (e.g. first push to branch)

## Notes

- Requires `fetch-depth: 0` (or at least enough history to compare against the base ref) in your
  checkout step.
- Per-app boolean outputs (`changed-api`, `changed-web`, `changed-client`) are useful for
  `if:` conditions when you don't need a matrix.
- App names are sanitized (lowercased, non-alphanumeric characters replaced with `_`) in the
  output key names.
