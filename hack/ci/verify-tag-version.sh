#!/usr/bin/env bash
set -euo pipefail
# Verifies that the git tag (GITHUB_REF_NAME) matches Chart.yaml version and appVersion.
# Under ACT, allow empty ref and fallback to Chart.yaml version.

VERSION=${GITHUB_REF_NAME#v}
CHART_VERSION=$(grep '^version:' Chart.yaml | awk '{print $2}')
APP_VERSION=$(grep '^appVersion:' Chart.yaml | awk '{print $2}' | tr -d '"')

if [ -z "${VERSION:-}" ]; then VERSION="$CHART_VERSION"; fi

echo "Tag version: $VERSION"
echo "Chart.yaml version: $CHART_VERSION"
echo "Chart.yaml appVersion: $APP_VERSION"

if [ "$VERSION" != "$CHART_VERSION" ]; then
  if [ "${IS_ACT:-}" = "true" ] || [ "${ACT:-}" = "true" ]; then
    echo "[act] Note: ignoring tag vs chart version mismatch under act (VERSION=$VERSION, CHART_VERSION=$CHART_VERSION)"
  else
    echo "ERROR: git tag version ($VERSION) != Chart.yaml version ($CHART_VERSION)" >&2
    exit 1
  fi
fi

if [ "$VERSION" != "$APP_VERSION" ]; then
  if [ "${IS_ACT:-}" = "true" ] || [ "${ACT:-}" = "true" ]; then
    echo "[act] Note: ignoring tag vs appVersion mismatch under act (VERSION=$VERSION, APP_VERSION=$APP_VERSION)"
  else
    echo "ERROR: git tag version ($VERSION) != Chart.yaml appVersion ($APP_VERSION)" >&2
    exit 1
  fi
fi
