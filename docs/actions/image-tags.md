---
title: Action — image-tags
---

# Action — image-tags

Computes the image name, tags, OCI labels and layer-cache reference of a
container build from the event that triggered it. [`cd-buildkit`](../workflows/cd-buildkit.md)
(both build paths) and [`cd-docker`](../workflows/cd-docker.md) use it, so
every image of these workflows is tagged and labelled alike. It needs bash and no checkout.

## Usage

```yaml
steps:
  - id: image
    uses: KevinDeBenedetti/github-workflows/.github/actions/image-tags@main
    with:
      version: v1.2.3

  - uses: docker/build-push-action@v7
    with:
      tags: ${{ steps.image.outputs.names }}
      cache-from: type=registry,ref=${{ steps.image.outputs.cache }}
```

## Inputs

| Input        | Default   | Description                                       |
| ------------ | --------- | ------------------------------------------------- |
| `image-name` | `''`      | Image name; empty uses the repository name        |
| `version`    | `''`      | Explicit version tag (`v1.2.3` also tags `1.2`)   |
| `tag-latest` | `'false'` | `'true'` also tags `latest` on the default branch |
| `registry`   | `ghcr.io` | Registry host                                     |

## Outputs

| Output     | Description                                                           |
| ---------- | --------------------------------------------------------------------- |
| `image`    | Image reference without a tag, `registry/owner/name`, lowercase       |
| `tags`     | The tags, space-separated                                             |
| `names`    | `image:tag` for each tag, comma-separated                             |
| `raw-tags` | One `type=raw,value=<tag>` line per tag, for `docker/metadata-action` |
| `cache`    | Registry layer-cache reference, `<image>-cache:buildcache`            |
| `labels`   | OCI labels, one `KEY=VALUE` line each (see [Labels](#labels))         |

## Tags

| Event                                  | Tags                                            |
| -------------------------------------- | ----------------------------------------------- |
| Any                                    | `sha-<7 characters>`                            |
| Push to a branch                       | `<branch>` (`/` and other characters → `-`)     |
| Pull request                           | `pr-<number>`                                   |
| Push of a release tag `vX.Y.Z`         | `X.Y.Z`, `X.Y`                                  |
| Push of a pre-release tag `vX.Y.Z-pre` | `X.Y.Z-pre`                                     |
| `version` set                          | the version as given, `X.Y` for a final release |
| `tag-latest` on the default branch     | `latest`                                        |

## Labels

The `org.opencontainers.image.*` keys `docker/metadata-action` sets, computed once
so that `cd-buildkit` and `cd-docker` label an image alike:

| Label         | Value                                                                                             |
| ------------- | ------------------------------------------------------------------------------------------------- |
| `title`       | The image name, as given                                                                          |
| `description` | The repository's description, left out when empty                                                 |
| `url`         | The repository's page                                                                             |
| `source`      | The repository's page                                                                             |
| `version`     | The most specific tag: `version`, the release tag's `X.Y.Z`, `pr-<n>`, the branch, else `sha-<7>` |
| `created`     | The build time, UTC                                                                               |
| `revision`    | The commit                                                                                        |
| `licenses`    | The repository's SPDX licence, left out when empty or `NOASSERTION`                               |

Each value is one line: control characters become spaces.

## Notes

- `X.Y` belongs to the final releases: a pre-release (`v1.3.0-rc.2`) keeps
  its own tag only. A release tag that is not `vX.Y.Z[-pre]` adds no version
  tag; `tests/fixtures/release-tags.tsv` holds the tags this rule shares with
  the other release-tag rules of the repository.
- A tag applied twice (a release tag pushed with the same `version`) appears
  once.
- [`cleanup-ghcr`](../workflows/cleanup-ghcr.md) keeps the `buildcache` tag of
  the layer caches; a test fails when the two names differ.
