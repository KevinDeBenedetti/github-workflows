---
title: Action — setup-promtool
---

# Action — setup-promtool

Installs [promtool](https://prometheus.io/docs/prometheus/latest/command-line/promtool/)
(from the Prometheus release) and [yq](https://github.com/mikefarah/yq) into
`$RUNNER_TEMP/bin`, added to `PATH`. It backs the install step of
[`ci-prometheus.yml`](../workflows/ci-prometheus.md).

## Usage

```yaml
steps:
  - uses: KevinDeBenedetti/github-workflows/.github/actions/setup-promtool@main
    with:
      promtool-version: X.Y.Z    # no leading v
      yq-version: vX.Y.Z         # with the leading v
```

## Inputs

| Input              | Default      | Description                                                    |
| ------------------ | ------------ | -------------------------------------------------------------- |
| `promtool-version` | *(required)* | Prometheus release providing promtool, without the leading `v` |
| `yq-version`       | *(required)* | `mikefarah/yq` release tag, with the leading `v`               |

## Steps

1. Pick the runner's architecture (`amd64` or `arm64`; anything else fails).
2. Download the Prometheus tarball and the release's `sha256sums.txt`, check the
   tarball against its line, and extract `promtool`.
3. Download the yq binary, the release's `checksums` and `checksums_hashes_order`,
   read the SHA-256 column that `checksums_hashes_order` names, and check the binary.
4. Add `$RUNNER_TEMP/bin` to `PATH`.

## Notes

- The versions are the caller's, so no checksum is pinned here, unlike
  [`install-tool`](install-tool.md): each asset is checked against the list
  published in its own release. That catches a corrupted or swapped asset, not a
  fully compromised release.
- A missing entry fails with the asset's name (`no SHA-256 for … in …`), and a
  failed check installs nothing on `PATH`.
- Downloads are retried 5 times, for GitHub's occasional 5xx.
- The script is `setup-promtool.sh`; its tests are in `tests/setup-promtool.bats`.
