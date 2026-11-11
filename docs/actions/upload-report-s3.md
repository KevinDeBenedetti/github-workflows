---
title: Action — upload-report-s3
---

# Action — upload-report-s3

Copies a report directory to S3-compatible storage, such as Backblaze B2, AWS S3
or MinIO, with [rclone](https://rclone.org/), and writes the path of the copy to the
job summary. The perf and SEO workflows run it when their `report-s3-bucket` input
is set: a report that lives outside GitHub costs no Actions storage.

## Usage

```yaml
steps:
  - uses: KevinDeBenedetti/github-workflows/.github/actions/upload-report-s3@main
    with:
      path: sitespeed-result
      name: sitespeed-result-desktop
      workflow: perf-sitespeed
      endpoint: https://s3.eu-central-003.backblazeb2.com
      bucket: my-perf-reports
      prefix: perf
      access-key-id: ${{ secrets.B2_KEY_ID }}
      secret-access-key: ${{ secrets.B2_APPLICATION_KEY }}
```

The report then lands under:

```text
<prefix>/<owner>/<repo>/<workflow>/<run id>-<run attempt>/<name>/
```

`<name>` is the report's artifact name, so the jobs of one run never write over each
other: the two devices of a sitespeed.io matrix, or two calls of perf-unlighthouse.

## Inputs

| Input               | Default    | Description                                                                  |
| ------------------- | ---------- | ---------------------------------------------------------------------------- |
| `path`              | (required) | Report directory to copy; a missing one is a warning, not an error           |
| `name`              | (required) | Folder of the report under the run, such as its artifact name                |
| `workflow`          | (required) | Workflow segment of the path: lowercase letters, digits and hyphens          |
| `endpoint`          | (required) | `https://` URL of the S3 API host                                            |
| `bucket`            | (required) | Bucket                                                                       |
| `prefix`            | `''`       | Key prefix before `<owner>/<repo>`; leading, trailing and doubled slashes go |
| `access-key-id`     | (required) | Access key ID (a B2 application key ID)                                      |
| `secret-access-key` | (required) | Secret access key (the B2 application key)                                   |

## Outputs

| Output | Description              |
| ------ | ------------------------ |
| `path` | `s3://` path of the copy |

## The bucket

::: warning Keep the bucket private
The reports are not meant for the public. A sitespeed.io result holds HAR files,
which record every request and response of the measured pages, headers included:
cookies, tokens in URLs, or whatever a page sets. Screenshots and videos show
the pages as rendered. Make the bucket **private** and share a report only with
a signed, short-lived link.
:::

- Give the bucket a **lifecycle rule** that deletes the reports after a few days
  or weeks; nothing else ever deletes them. On B2, a custom rule sets the *days
  from uploading to hiding*, then the *days from hiding to deleting*.
- A **write-only key** is enough: rclone runs with `--no-check-dest`,
  `no_check_bucket` and `no_head`, so it lists, reads and creates nothing. On B2,
  an application key restricted to the bucket with *Write Only* access keeps the
  blast radius small if the key leaks.
- The region is read from Backblaze B2 and AWS endpoints (`s3.<region>.backblazeb2.com`,
  `s3.<region>.amazonaws.com`), and left blank for other services.

## Notes

- rclone is downloaded at the pinned version and checked against the pinned SHA-256
  of its `.deb` before it runs. `dpkg-deb`, in every Debian and Ubuntu image, unpacks
  the package without root, where unzip may be missing (the sitespeed.io image has
  none). Renovate bumps the version; refresh the checksums with
  `scripts/update-tool-checksums.py`, which cross-checks them against the release's
  `SHA256SUMS`.
- The credentials reach rclone through its environment only: never on a command
  line, never in a file, never printed. Its configuration file is empty, so a stray
  `~/.config/rclone/rclone.conf` or `AWS_*` variable is never read.
- A failed copy fails the step. Needs bash, curl or wget, `sha256sum` and
  `dpkg-deb`: Debian or Ubuntu, inside a job container too.
- The script is `upload-report-s3.sh`; its tests are in `tests/upload-report-s3.bats`.
