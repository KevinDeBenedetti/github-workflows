---
title: Action — image-scan
---

# Action — image-scan

Scans a container image for known vulnerabilities (OS packages and language libraries)
with [Trivy](https://github.com/aquasecurity/trivy). It is the scan step of
[`cd-docker.yml`](../workflows/cd-docker.md) and
[`ci-docker.yml`](../workflows/ci-docker.md), which build and load the image before it.

## Usage

```yaml
steps:
  - run: docker build -t my-api:scan .

  - uses: KevinDeBenedetti/github-workflows/.github/actions/image-scan@v0.56.2 # x-release-please-version
    with:
      image: my-api:scan
      fail-on: critical
```

## Inputs

| Input     | Default      | Description                                                                |
| --------- | ------------ | -------------------------------------------------------------------------- |
| `image`   | *(required)* | Image reference to scan, loaded in the runner's Docker daemon              |
| `fail-on` | `critical`   | Lowest severity that fails the step: `low`, `medium`, `high` or `critical` |

## Steps

1. Install the pinned `trivy` with [`install-tool`](install-tool.md)
2. Restore the vulnerability database from the Actions cache (one entry per day and runner architecture)
3. `trivy image --scanners vuln` on `image`, for the severities at `fail-on` and above
4. List each vulnerability in the job summary (package, identifier, severity, installed and fixed versions); the step fails when there is one

## Notes

- A vulnerability counts whether a fix exists or not. Silence one with its identifier in a `.trivyignore` file at the root of the checkout.
- The image must be in the Docker daemon: a multi-platform build cannot be loaded, so scan the runner's platform.
- No SARIF is written: the findings are in the job summary and the log.
- The script is `image-scan.sh`; its tests are in `tests/image-scan.bats`.
