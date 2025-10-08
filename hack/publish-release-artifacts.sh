#!/usr/bin/env bash
set -euo pipefail
# publish-release-artifacts.sh
# Automate packaging, git tagging (signed if possible), OCI push, optional signing, SBOM, scan, attest.
# Usage: publish-release-artifacts.sh --version X.Y.Z --org myorg [--sign] [--sbom] [--scan] [--attest] [--provenance] [--push-tag]
#   --provenance: generate slsa-provenance.json (hack/generate-provenance.sh) and, if --attest also set, attach with cosign --type slsaprovenance
# Requirements: helm, git, optionally gpg, cosign, syft, grype.

VERSION=""
ORG=""
DO_SIGN=0
DO_SBOM=0
DO_SCAN=0
DO_ATTEST=0
DO_PROVENANCE=0
PUSH_TAG=0
OCI_PREFIX="ghcr.io"

usage(){
  echo "Usage: $0 --version X.Y.Z --org ORG [--sign] [--sbom] [--scan] [--attest] [--push-tag]" >&2
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --version) VERSION=$2; shift 2;;
    --org) ORG=$2; shift 2;;
    --sign) DO_SIGN=1; shift;;
    --sbom) DO_SBOM=1; shift;;
    --scan) DO_SCAN=1; shift;;
    --attest) DO_ATTEST=1; shift;;
  --provenance) DO_PROVENANCE=1; shift;;
    --push-tag) PUSH_TAG=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

[[ -z $VERSION || -z $ORG ]] && { usage; exit 2; }

echo "[release] Packaging chart version $VERSION"
helm package . --version "$VERSION" --app-version "$VERSION"

echo "[release] Creating git tag v$VERSION (signed if possible)"
if command -v gpg >/dev/null 2>&1; then
  if ! git tag -s "v$VERSION" -m "Release v$VERSION" 2>/dev/null; then
    echo "[release] GPG signing failed or not configured, creating unsigned tag" >&2
    git tag "v$VERSION" -f
  fi
else
  git tag "v$VERSION" -f
fi
if (( PUSH_TAG==1 )); then
  git push origin "v$VERSION"
fi

echo "[release] Pushing OCI artifact"
helm push "rulehub-policies-$VERSION.tgz" oci://$OCI_PREFIX/$ORG/charts

if (( DO_SIGN==1 )); then
  echo "[release] Signing OCI artifact (cosign keyless)"
  COSIGN_EXPERIMENTAL=1 cosign sign $OCI_PREFIX/$ORG/charts/rulehub-policies:$VERSION || echo "[release] cosign sign failed" >&2
fi

if (( DO_PROVENANCE==1 )); then
  echo "[release] Generating SLSA provenance predicate"
  bash hack/generate-provenance.sh --version "$VERSION" --package --out slsa-provenance.json || echo "[release] provenance generation failed" >&2
fi

if (( DO_SBOM==1 )); then
  echo "[release] Generating SBOM (syft)"
  syft oci:$OCI_PREFIX/$ORG/charts/rulehub-policies:$VERSION -o spdx-json=sbom.spdx.json || echo "[release] syft failed" >&2
fi

if (( DO_SCAN==1 )); then
  echo "[release] Scanning vulnerabilities (grype)"
  grype -o json oci:$OCI_PREFIX/$ORG/charts/rulehub-policies:$VERSION > grype.json || echo "[release] grype failed" >&2
fi

if (( DO_ATTEST==1 )); then
  echo "[release] Attesting available artifacts (cosign)"
  [[ -f sbom.spdx.json ]] && COSIGN_EXPERIMENTAL=1 cosign attest --predicate sbom.spdx.json --type spdx $OCI_PREFIX/$ORG/charts/rulehub-policies:$VERSION || true
  [[ -f grype.json ]] && COSIGN_EXPERIMENTAL=1 cosign attest --predicate grype.json --type vuln $OCI_PREFIX/$ORG/charts/rulehub-policies:$VERSION || true
fi

echo "[release] Completed publication for $VERSION"
