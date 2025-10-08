#!/usr/bin/env bash
set -euo pipefail

# verify-kubeconform-checksum.sh
# Verify that the downloaded kubeconform release artifact matches the pinned
# sha256 checksum stored in hack/checksums/kubeconform-v<version>.CHECKSUMS.
#
# Features:
#  - Supports all OS/ARCH pairs present in the pinned checksums file.
#  - Defaults: version=v0.7.0, os=linux, arch=amd64.
#  - Optional --install: installs the binary into /usr/local/bin after verification.
#  - Fails with clear diagnostics on mismatch or missing checksum.
#
# Usage examples:
#   bash hack/verify-kubeconform-checksum.sh                      # linux/amd64 v0.7.0
#   bash hack/verify-kubeconform-checksum.sh --os darwin --arch arm64
#   bash hack/verify-kubeconform-checksum.sh --version v0.7.0 --os windows --arch amd64
#   bash hack/verify-kubeconform-checksum.sh --install           # verify + install
#
# Exit codes:
#   0 - success (match)
#   1 - checksum mismatch
#   2 - usage / argument error
#   3 - expected checksum not found

VERSION="v0.7.0"
OS="linux"
ARCH="amd64"
INSTALL=0
CHECKSUMS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/checksums && pwd)"

usage() {
  grep '^# ' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2;;
    --os) OS="$2"; shift 2;;
    --arch) ARCH="$2"; shift 2;;
    --install) INSTALL=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown argument: $1" >&2; exit 2;;
  esac
done

FILE_EXT="tar.gz"
if [[ "$OS" == "windows" ]]; then
  FILE_EXT="zip"
fi

CHECKSUM_FILE="${CHECKSUMS_DIR}/kubeconform-${VERSION}.CHECKSUMS"
if [[ ! -f "$CHECKSUM_FILE" ]]; then
  echo "Pinned checksums file not found: $CHECKSUM_FILE" >&2
  exit 3
fi

ARTIFACT="kubeconform-${OS}-${ARCH}.${FILE_EXT}"

# Extract expected hash (handle potential multiple spaces)
EXPECTED_LINE=$(grep -E "[[:space:]]${ARTIFACT}$" "$CHECKSUM_FILE" || true)
if [[ -z "$EXPECTED_LINE" ]]; then
  echo "Expected checksum not found for artifact: $ARTIFACT (version $VERSION)" >&2
  exit 3
fi
EXPECTED_HASH=$(echo "$EXPECTED_LINE" | awk '{print $1}')

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

BASE_URL="https://github.com/yannh/kubeconform/releases/download/${VERSION}"
ARTIFACT_PATH="$TMP_DIR/$ARTIFACT"

echo "Downloading $ARTIFACT (version $VERSION) ..." >&2
curl -sSL "${BASE_URL}/${ARTIFACT}" -o "$ARTIFACT_PATH"

ACTUAL_HASH=$(sha256sum "$ARTIFACT_PATH" | awk '{print $1}')
echo "Expected: $EXPECTED_HASH" >&2
echo "Actual:   $ACTUAL_HASH" >&2

if [[ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]]; then
  echo "Checksum mismatch for $ARTIFACT" >&2
  exit 1
fi

echo "Checksum OK for $ARTIFACT" >&2

if (( INSTALL )); then
  echo "Installing kubeconform -> /usr/local/bin (requires write perms)" >&2
  if [[ "$FILE_EXT" == "tar.gz" ]]; then
    tar -xzf "$ARTIFACT_PATH" -C "$TMP_DIR" kubeconform
    sudo install "$TMP_DIR/kubeconform" /usr/local/bin/kubeconform
  else
    unzip -q "$ARTIFACT_PATH" -d "$TMP_DIR"
    sudo install "$TMP_DIR/kubeconform.exe" /usr/local/bin/kubeconform.exe
  fi
fi
