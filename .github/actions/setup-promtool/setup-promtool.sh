#!/usr/bin/env bash
# Install promtool (from the Prometheus release) and yq into $RUNNER_TEMP/bin,
# each checked against the SHA-256 list published in its own release, then
# add that directory to PATH.
#
# Both versions are caller inputs, so no checksum can be pinned here (unlike
# install-tool/tools.json): the release's own list catches a corrupted or
# swapped asset, not a fully compromised release.
#
# Env: PROMTOOL_VERSION   Prometheus release, without the leading v
#      YQ_VERSION         mikefarah/yq release tag, with the leading v
#      RUNNER_TEMP        set by the runner
#      GITHUB_PATH        set by the runner
set -euo pipefail

case "$(uname -m)" in
  x86_64)  arch=amd64 ;;
  aarch64) arch=arm64 ;;
  *) echo "::error::unsupported arch: $(uname -m)"; exit 1 ;;
esac
bin="${RUNNER_TEMP}/bin"
dl="${RUNNER_TEMP}/dl"
mkdir -p "$bin" "$dl"
# GitHub's release downloads answer an occasional 5xx: retried, like the tool
# installs of the composite actions, instead of failing the job.
download() { curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors -o "$1" "$2"; }

prom="prometheus-${PROMTOOL_VERSION}.linux-${arch}.tar.gz"
base="https://github.com/prometheus/prometheus/releases/download/v${PROMTOOL_VERSION}"
download "$dl/$prom" "$base/$prom"
download "$dl/prom-sha256sums.txt" "$base/sha256sums.txt"
want=$(awk -v f="$prom" '$2 == f {print $1}' "$dl/prom-sha256sums.txt")
echo "${want:?no SHA-256 for $prom in sha256sums.txt}  $dl/$prom" | sha256sum --check --strict --quiet -
tar -xz -C "$bin" --strip-components=1 -f "$dl/$prom" "prometheus-${PROMTOOL_VERSION}.linux-${arch}/promtool"

# yq publishes one `checksums` file with ~20 hash columns; their order is
# listed in `checksums_hashes_order` (column 1 is the name).
yq="yq_linux_${arch}"
base="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}"
download "$dl/$yq" "$base/$yq"
download "$dl/yq-checksums" "$base/checksums"
download "$dl/yq-checksums-order" "$base/checksums_hashes_order"
col=$(grep -nx 'SHA-256' "$dl/yq-checksums-order" | cut -d: -f1 || true)
want=$(awk -v f="$yq" -v c="$(( ${col:?SHA-256 not listed in checksums_hashes_order} + 1 ))" '$1 == f {print $c}' "$dl/yq-checksums")
echo "${want:?no SHA-256 for $yq in checksums}  $dl/$yq" | sha256sum --check --strict --quiet -
install -m 0755 "$dl/$yq" "$bin/yq"
echo "$bin" >> "$GITHUB_PATH"
