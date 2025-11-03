#!/usr/bin/env bash
set -euo pipefail

TAG_RAW=$(git describe --tags --abbrev=0 2>/dev/null || true)
if [[ -z "${TAG_RAW}" ]]; then
  echo "No git tags found (expected vX.Y.Z)." >&2
  exit 1
fi
if [[ ! ${TAG_RAW} =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Latest tag ${TAG_RAW} not semver (vX.Y.Z)." >&2
  exit 1
fi
FILE_VER=$(grep '^version:' Chart.yaml | awk '{print $2}')
APP_VER=$(grep '^appVersion:' Chart.yaml | awk '{print $2}' | tr -d '"')
echo "Tag:       ${TAG_RAW}"
echo "Chart ver: ${FILE_VER}"
echo "appVersion:${APP_VER}"
if [[ "v${FILE_VER}" != "${TAG_RAW}" ]]; then
  echo "Mismatch tag vs Chart.yaml version" >&2
  exit 2
fi
echo "OK"
