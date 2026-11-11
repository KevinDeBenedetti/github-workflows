---
title: Action — setup-jq
---

# Action — setup-jq

Installs [jq](https://jqlang.org/), pinned by version and SHA-256, into the runner's
temporary directory and puts it on `PATH`. It is meant for a job container whose image
has no jq, such as the sitespeed.io image the perf workflows run in. It downloads with
curl, or with wget where the image has no curl, and needs no root.

## Usage

```yaml
jobs:
  audit:
    container:
      image: sitespeedio/sitespeed.io:<tag>@sha256:<digest>
    steps:
      - uses: KevinDeBenedetti/github-workflows/.github/actions/setup-jq@main
      - run: jq --version
```

## Notes

- No input: the version and the SHA-256 of each architecture's binary (amd64,
  arm64) are pinned in the action. Renovate bumps the version; refresh the checksums
  with `scripts/update-tool-checksums.py`, which cross-checks them against the
  release's `sha256sum.txt`. A download that does not match fails the step.
- The binary lands in `$RUNNER_TEMP/jq`, inside the container too, and is added
  through `GITHUB_PATH` for the next steps of the job.
