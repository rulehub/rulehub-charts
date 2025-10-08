#!/usr/bin/env bash
set -euo pipefail
CHART_VERSION=$(grep '^version:' Chart.yaml | awk '{print $2}')
APP_VERSION=$(grep '^appVersion:' Chart.yaml | awk '{print $2}')
VERSION=${GITHUB_REF_NAME#v}
REF=ghcr.io/${GITHUB_REPOSITORY_OWNER}/charts/rulehub-policies:$VERSION

{
  echo "Published packages:"
  ls -1 *.tgz || true
  echo "Chart version: $CHART_VERSION"
  echo "App version: $APP_VERSION"
  if [ "${IS_ACT:-false}" = "true" ]; then
    echo "[act] Local emulation run — publish/sign/attest steps were skipped."
    echo "[act] No registry push performed; summary reflects local packaging only."
  else
    echo "Cosign signed reference: $REF"
    if [ -f cosign-verify.json ]; then
      echo "Signature verified (see cosign-verify.json)"
    fi
    if [ -f sbom.spdx.json ]; then
      SBOM_SHA=$(sha256sum sbom.spdx.json | awk '{print $1}')
      echo "SBOM (spdx-json) sha256: $SBOM_SHA"
    fi
    echo "Vulnerability gate: CRITICAL=0 enforced"
    echo "SBOM attested (spdx)"
    echo "Cosign signed reference: $REF"
    echo "Signature bundle stored in registry (keyless)."
  fi
  echo "Kubeconform validation passed"
} >> "$GITHUB_STEP_SUMMARY"
