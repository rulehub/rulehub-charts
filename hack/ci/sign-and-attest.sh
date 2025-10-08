#!/usr/bin/env bash
set -euo pipefail

# sign-and-attest.sh
# Sign chart OCI artifact, verify signature, generate SBOM, run vulnerability gate,
# and create + verify SBOM and provenance attestations.
#
# Inputs (env):
#   ORG      - GitHub org/owner (e.g., ${{ github.repository_owner }})
#   VERSION  - version without leading 'v' (e.g., 0.1.0)
#
# Requirements:
#   - cosign, syft installed in CI image
#   - slsa-provenance.json present (generated earlier)

ORG=${ORG:?ORG is required}
VERSION=${VERSION:?VERSION is required}
REF="ghcr.io/${ORG}/charts/rulehub-policies:${VERSION}"

export COSIGN_EXPERIMENTAL=true

echo "[sign] Signing ${REF} via keyless OIDC"
cosign sign --yes "$REF"

echo "[verify] Verifying signature for ${REF}"
cosign verify "$REF" > cosign-verify.json
echo '[verify] Cosign verification output (truncated):'
head -40 cosign-verify.json || true

echo "[sbom] Generating SBOM (spdx-json) for ${REF}"
syft "$REF" -o spdx-json=sbom.spdx.json
echo "[sbom] SBOM size: $(wc -c < sbom.spdx.json)"

echo "[vulns] Running vulnerability gate (CRITICAL=0)"
bash hack/verify-vulns.sh --org "$ORG" --version "$VERSION" --severity CRITICAL --allow 0 --list 5

echo "[attest] Attesting SBOM"
cosign attest --predicate sbom.spdx.json --type spdx "$REF"

echo "[attest] Attesting SLSA provenance"
cosign attest --predicate slsa-provenance.json --type https://slsa.dev/provenance/v1 "$REF"

echo "[attest-verify] Verifying SBOM and SLSA attestations (truncated)"
echo 'Verifying SBOM attestation:'
cosign verify-attestation --type spdx "$REF" | head -40 || true
echo 'Verifying SLSA provenance attestation:'
cosign verify-attestation --type https://slsa.dev/provenance/v1 "$REF" | head -40 || true

echo '[sign-and-attest] Done.'
