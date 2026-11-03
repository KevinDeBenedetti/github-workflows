---
title: Pre-release
---

# Pre-release

Publishes pre-releases of a long-lived integration branch, such as `dev`, whose final
releases ship from another branch through [release.yml](./release.md). Each pre-release is
`v<next>-<type>.<n>`, a GitHub pre-release tagged on the commit and never marked latest.
Nothing is asked of anyone: each releasable push is pre-released. To review and merge a
pull request for each pre-release instead, run release-please on that branch too:
[release.yml](./release.md#pre-releases-from-a-second-branch), with `target-branch`.

## Usage

A pipeline that bakes the version into its build computes it first, then publishes it once
the deploy succeeded. Both calls give the same tag for the same commit.

```yaml
jobs:
  prerelease-plan:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/prerelease.yml@main
    permissions:
      contents: write

  build:
    needs: prerelease-plan
    # Bake it in, and tag the image with it: cd-buildkit.yml's `version`.
    # ... ${{ needs.prerelease-plan.outputs.tag || format('sha-{0}', github.sha) }}

  prerelease-publish:
    needs: [prerelease-plan, deploy]
    if: needs.prerelease-plan.outputs.tag != ''
    uses: KevinDeBenedetti/github-workflows/.github/workflows/prerelease.yml@main
    with:
      publish: true
      tag: ${{ needs.prerelease-plan.outputs.tag }}
    permissions:
      contents: write
```

Both calls grant `contents: write`: GitHub refuses a called job asking for more than its
caller grants, and the job asks for it whatever `publish` says. The token is used only to
publish.

## Inputs

| Input             | Type    | Default           | Description                                                                                          |
| ----------------- | ------- | ----------------- | ---------------------------------------------------------------------------------------------------- |
| `publish`         | boolean | `false`           | Create the tag and the GitHub pre-release; `false` only computes it                                  |
| `tag`             | string  | `''`              | With `publish`, the tag an earlier call computed, checked against this run's                         |
| `prerelease-type` | string  | `rc`              | Pre-release identifier                                                                               |
| `config-file`     | string  | `''`              | release-please config holding the bump rules; empty looks in `.github/release/`, then the repo root |
| `runner`          | string  | `"ubuntu-latest"` | Runner labels as JSON                                                                                |

## Outputs

| Output       | Description                                                                         |
| ------------ | ----------------------------------------------------------------------------------- |
| `releasable` | `true` when a feat, fix, perf, revert or breaking change landed since the last tag  |
| `tag`        | The pre-release tag (e.g. `v1.3.0-rc.7`), empty when not releasable                 |
| `version`    | The tag without its `v`                                                             |
| `base-tag`   | The last final tag the commit contains (e.g. `v1.2.4`), empty before any release    |

## How the version is computed

- **The base** is the highest `vX.Y.Z` tag the commit contains. Pre-release tags such as
  `v1.2.3-rc.4` and alias tags such as `v1.2` are ignored.
- **The next version** bumps the base the way release-please does: a breaking change bumps
  the major, a `feat` the minor, a `fix`, `perf` or `revert` the patch.
  `bump-minor-pre-major` and `bump-patch-for-minor-pre-major` come from the release-please
  config, the package `.` setting first. Other types release nothing.
- **The number** `<n>` counts the commits since the base. It is unique per commit of the
  branch, so it is known before the build, and two runs never compete for it.

## Notes

- **Why not release-please on the branch.** It would track its own pre-release PRs there and,
  after each final release, keep counting from its last pre-release: `0.23.0-rc.3` once
  `0.23.0` is out. Starting from the last final tag stays right across releases.
- **release-please on the release branch is unaffected.** It looks for the tag of its
  manifest version and ignores these.
- **The branch must contain the last release.** After a final release, merge the release
  branch back into the integration branch. Until then the job fails rather than publish a
  pre-release below a version already out, such as `v0.22.1-rc.10` after `v0.22.1`.
- **The tag works as an image version.** Given to [cd-buildkit.yml](./cd-buildkit.md) as
  `version`, it tags the image `v1.3.0-rc.7` with no `1.3` alias, which belongs to the final
  releases; a deploy that points the infrastructure at that tag records the version each
  environment runs.
- **A re-run publishes nothing twice.** An existing pre-release on the same commit is left
  alone; a tag of the same name on another commit, after a rewritten branch, fails the job.
- **No workflow runs on these tags.** They are created with the job's `GITHUB_TOKEN`, whose
  events start no workflow.
- The release notes group the commits like release-please's changelog, with commit links.
