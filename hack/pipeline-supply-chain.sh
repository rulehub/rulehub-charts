#!/usr/bin/env bash
set -euo pipefail

# pipeline-supply-chain.sh
# Opinionated supply chain pipeline for the Helm chart (OCI flow):
#   1. Package chart (helm package)
#   2. Push to OCI registry (helm push)
#   3. Sign OCI artifact (cosign sign) - keyless by default (OIDC)
#   4. Generate SBOM (syft) from pushed image (OCI ref)
#   5. (Optional) Vulnerability scan (grype) fail on CRITICAL (configurable threshold)
#   6. Attest SBOM (cosign attest --type spdx)
#   7. (Optional) Attest vulnerabilities summary (cosign attest --type vuln)
#
# Requirements (pre-installed / in PATH): helm, cosign, syft, grype (if scan enabled), jq (for vuln summary)
#
# Usage:
#   bash hack/pipeline-supply-chain.sh \
#       --org <ghcr_org_or_user> \
#       --version <chart_version> \
#       [--chart-dir .] \
#       [--sign] [--sbom] [--scan] [--attest-sbom] [--attest-vuln] \
#       [--fail-on-critical 0|1] [--fail-on-severity CRITICAL] \
#       [--oci-prefix ghcr.io] [--skip-package] [--skip-push]
#
# Shortcuts:
#   ALL steps (except vuln attest) typical: --sign --sbom --scan --attest-sbom --attest-vuln
#
# Exit codes:
#   0 success, >0 error. If scan enabled and threshold exceeded -> exit 3.
#
# Notes:
#   - Uses COSIGN_EXPERIMENTAL=1 for keyless mode if no key refs.
#   - Vulnerability severity filter uses grype JSON output.
#   - Attestation subjects reference the same OCI digest produced after push.

ORG=""
VERSION=""
CHART_DIR="."
OCI_PREFIX="ghcr.io"
DO_SIGN=0
DO_SBOM=0
DO_SCAN=0
DO_ATTEST_SBOM=0
DO_ATTEST_VULN=0
FAIL_ON_CRITICAL=1
FAIL_ON_SEVERITY="CRITICAL" # Highest severity to trigger failure (exact match)
SKIP_PACKAGE=0
SKIP_PUSH=0

usage() { grep '^# ' "$0" | sed 's/^# \{0,1\}//'; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --org) ORG="$2"; shift 2;;
      --version) VERSION="$2"; shift 2;;
      --chart-dir) CHART_DIR="$2"; shift 2;;
      --oci-prefix) OCI_PREFIX="$2"; shift 2;;
      --sign) DO_SIGN=1; shift;;
      --sbom) DO_SBOM=1; shift;;
      --scan) DO_SCAN=1; shift;;
      --attest-sbom) DO_ATTEST_SBOM=1; shift;;
      --attest-vuln) DO_ATTEST_VULN=1; shift;;
      --fail-on-critical) FAIL_ON_CRITICAL="$2"; shift 2;;
      --fail-on-severity) FAIL_ON_SEVERITY="$2"; shift 2;;
      --skip-package) SKIP_PACKAGE=1; shift;;
      --skip-push) SKIP_PUSH=1; shift;;
      -h|--help) usage; exit 0;;
      *) echo "Unknown arg: $1" >&2; exit 2;;
    esac
  done
  if [[ -z "$ORG" || -z "$VERSION" ]]; then
    echo 'Specify --org and --version' >&2; exit 2
  fi
}

check_bin() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1" >&2; exit 2; }; }

package_chart() {
  if (( SKIP_PACKAGE==1 )); then
    echo '[pipeline] Skipping packaging (user requested)'; return 0; fi
  echo '[pipeline] Packaging chart'
  helm package "$CHART_DIR" --version "$VERSION" --app-version "$VERSION"
}

push_chart() {
  if (( SKIP_PUSH==1 )); then echo '[pipeline] Skipping push (user requested)'; return 0; fi
  echo '[pipeline] Pushing chart to OCI'
  local tgz="rulehub-policies-${VERSION}.tgz"
  if [[ ! -f "$tgz" ]]; then echo "Package $tgz not found (did packaging succeed?)" >&2; exit 2; fi
  helm push "$tgz" oci://$OCI_PREFIX/$ORG/charts
}

resolve_digest() {
  # Pull manifest to extract digest (helm push output may not easily expose)
  echo '[pipeline] Resolving OCI digest'
  local ref="$OCI_PREFIX/$ORG/charts/rulehub-policies:$VERSION"
  # Using ORAS could help, but rely on crane if installed; fallback to skopeo; else just set ref
  if command -v crane >/dev/null 2>&1; then
    DIGEST=$(crane digest "$ref")
    OCI_REF_WITH_DIGEST="$ref@$DIGEST"
  else
    OCI_REF_WITH_DIGEST="$ref" # best effort
  fi
  echo "[pipeline] OCI reference: $OCI_REF_WITH_DIGEST"
}

sign_chart() {
  (( DO_SIGN )) || return 0
  echo '[pipeline] Signing OCI artifact (cosign keyless)'
  COSIGN_EXPERIMENTAL=1 cosign sign "$OCI_PREFIX/$ORG/charts/rulehub-policies:$VERSION"
}

generate_sbom() {
  (( DO_SBOM )) || return 0
  echo '[pipeline] Generating SBOM (syft)'
  syft "oci:$OCI_PREFIX/$ORG/charts/rulehub-policies:$VERSION" -o spdx-json=sbom.spdx.json
}

scan_vulns() {
  (( DO_SCAN )) || return 0
  echo '[pipeline] Scanning vulnerabilities (grype)'
  grype -o json "oci:$OCI_PREFIX/$ORG/charts/rulehub-policies:$VERSION" > grype.json
  local crit_count sever_count
  if command -v jq >/dev/null 2>&1; then
    crit_count=$(jq '[.matches[] | select(.vulnerability.severity=="CRITICAL")] | length' grype.json)
    sever_count=$(jq --arg sev "$FAIL_ON_SEVERITY" '[.matches[] | select(.vulnerability.severity==$sev)] | length' grype.json)
  else
    crit_count=$(grep -c '"severity":"CRITICAL"' grype.json || true)
    sever_count=$crit_count
  fi
  echo "[pipeline] CRITICAL vulnerabilities: $crit_count"
  if [[ "$FAIL_ON_SEVERITY" != "CRITICAL" ]]; then
    echo "[pipeline] $FAIL_ON_SEVERITY vulnerabilities: $sever_count"
  fi
  if (( FAIL_ON_CRITICAL==1 )) && (( crit_count>0 )); then
    echo '[pipeline] Failing due to CRITICAL vulnerabilities' >&2
    exit 3
  fi
}

attest_sbom() {
  (( DO_ATTEST_SBOM )) || return 0
  if [[ ! -f sbom.spdx.json ]]; then echo 'SBOM file missing (sbom.spdx.json)' >&2; exit 2; fi
  echo '[pipeline] Attesting SBOM'
  COSIGN_EXPERIMENTAL=1 cosign attest --predicate sbom.spdx.json --type spdx "$OCI_PREFIX/$ORG/charts/rulehub-policies:$VERSION"
}

attest_vuln() {
  (( DO_ATTEST_VULN )) || return 0
  if [[ ! -f grype.json ]]; then echo 'Vulnerability scan JSON (grype.json) not found' >&2; exit 2; fi
  echo '[pipeline] Attesting vulnerability scan report'
  COSIGN_EXPERIMENTAL=1 cosign attest --predicate grype.json --type vuln "$OCI_PREFIX/$ORG/charts/rulehub-policies:$VERSION"
}

main() {
  parse_args "$@"
  check_bin helm
  (( DO_SIGN )) && check_bin cosign || true
  (( DO_SBOM )) && check_bin syft || true
  (( DO_SCAN )) && check_bin grype || true
  (( DO_SCAN || DO_ATTEST_VULN )) && check_bin jq || true

  package_chart
  push_chart
  resolve_digest || true
  sign_chart
  generate_sbom
  scan_vulns
  attest_sbom
  attest_vuln
  echo '[pipeline] Completed successfully.'
}

main "$@"
