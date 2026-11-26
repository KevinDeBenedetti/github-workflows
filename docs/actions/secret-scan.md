---
title: Action — secret-scan
---

# Action — secret-scan

Scans the commits a run brings for leaked secrets with
[Gitleaks](https://github.com/gitleaks/gitleaks). The configuration and the
ignore list are read from a **trusted commit**, never from the commits under
scan, so a change cannot allowlist its own leak. It is the secret scan of
[`security.yml`](../workflows/security.md), which adds the checkout and the
SARIF upload around it.

## Usage

```yaml
steps:
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
    with:
      fetch-depth: 0 # the scan walks base..HEAD
      persist-credentials: false

  - id: base
    uses: KevinDeBenedetti/github-workflows/.github/actions/change-base@v0.56.2 # x-release-please-version
  - uses: KevinDeBenedetti/github-workflows/.github/actions/secret-scan@v0.56.2 # x-release-please-version
    with:
      base: ${{ steps.base.outputs.base }}
```

## Inputs

| Input                 | Default         | Description                                                                                                             |
| --------------------- | --------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `base`                | `''`            | The change base: the `base` output of [`change-base`](change-base.md), run without `fetch-base`. Empty scans everything |
| `ignore-inline-allow` | `false`         | Ignore inline `gitleaks:allow` comments (`gitleaks --ignore-gitleaks-allow`)                                            |
| `report-path`         | `results.sarif` | SARIF report to write                                                                                                   |

The step fails (exit `1`) when Gitleaks finds a leak. Findings are redacted
in the log; the SARIF report holds their file and line.

## Scanned range

- With a change base: `base..HEAD`, merge commits left out. No
  `--first-parent`: on a pull request `HEAD` is the merge commit GitHub
  prepares, and after a merge to the default branch the feature commits sit
  behind the second parent.
- Without one (a manual or scheduled run, a change base outside a shallow
  clone): all fetched history.

## Trusted commit

| Run                  | `.gitleaks.toml` and `.gitleaksignore` are read from                      |
| -------------------- | ------------------------------------------------------------------------- |
| A change base is set | The change base                                                           |
| Manual run           | The default branch, when the clone holds it                               |
| Scheduled run        | `HEAD`, the default branch's own tip                                      |
| Anything else        | Nowhere: Gitleaks' default rules and an empty ignore list, with a warning |

- A trusted `.gitleaks.toml` that `[extend]`s a `path` inside the repository
  gets that file restored from the trusted commit too. A path outside the
  repository (absolute, or with `..`), or missing from the trusted commit,
  fails the step.
- The working tree's `.gitleaksignore` is overwritten with the trusted copy:
  Gitleaks always reads it, on top of the one it is given.
- With a range, the step warns when the range changes the configuration, the
  ignore list or the extended file (not applied to this scan), and when it
  adds `gitleaks:allow` comments.

## Notes

- Pass `base` from `change-base` **without** `fetch-base`: the scan walks the
  commits between the base and `HEAD`, which a fetched single commit does not
  provide. A `base` that is not in the clone fails the step.
- Gitleaks is installed by [`install-tool`](install-tool.md): downloaded from
  its GitHub release and checked against the SHA-256 pinned in that action's
  `tools.json`. It needs `python3` on the runner, and runner 2.336.0 or newer
  for the nested `uses: $/…` call.
- Locally, with `gitleaks` on the `PATH`:
  `BASE=<sha> bash .github/actions/secret-scan/secret-scan.sh`.
