#!/usr/bin/env bash
set -euo pipefail

# verify-vulns.sh
# Policy gate: fail if CRITICAL (or configured severity) vulnerabilities are found in pushed OCI Helm chart.
# Intended to run after packaging & pushing chart to OCI registry.
#
# Usage:
#   bash hack/verify-vulns.sh --org <org> --version <chartVersion> [--severity CRITICAL] [--allow 0] [--oci-prefix ghcr.io] [--list 5]
#
# Options:
#   --org <org>            GitHub org / registry namespace
#   --version <ver>        Chart version (must match packaged / pushed tag)
#   --severity <sev>       Gate threshold (Negligible|Low|Medium|High|CRITICAL) (default: CRITICAL)
#   --allow <N>            Allow up to N findings (>= threshold) before failing (default: 0)
#   --oci-prefix <host>    Registry host prefix (default: ghcr.io)
#   --list <N>             Print top N (by severity desc) findings for context (default: 0 = none)
#   -h|--help              Show this help
#
# Requirements: grype, jq (optional for precise filtering). If jq absent, fallback counts only exact severity.
# Notes:
#   - Helm chart contents are YAML; normally zero vulns. Gate acts as hygiene & defense-in-depth.
#   - The scan uses the OCI chart ref; ensure `helm push` already executed.

ORG=""
VERSION=""
OCI_PREFIX="ghcr.io"
SEVERITY="CRITICAL"
ALLOW=0
LIST_TOP=0

usage() { grep '^# ' "$0" | sed 's/^# \{0,1\}//'; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --org) ORG="$2"; shift 2;;
      --version) VERSION="$2"; shift 2;;
      --severity) SEVERITY="${2^^}"; shift 2;;
      --allow) ALLOW="$2"; shift 2;;
      --oci-prefix) OCI_PREFIX="$2"; shift 2;;
      --list) LIST_TOP="$2"; shift 2;;
      -h|--help) usage; exit 0;;
      *) echo "[vulns] Unknown arg: $1" >&2; exit 2;;
    esac
  done
  if [[ -z "$ORG" || -z "$VERSION" ]]; then
    echo '[vulns] Specify --org and --version' >&2; exit 2
  fi
}

check_bin() { command -v "$1" >/dev/null 2>&1 || { echo "[vulns] Missing required tool: $1" >&2; exit 2; }; }

rank_of() {
  # Map severity to numeric rank
  case "$1" in
    NEGLIGIBLE|UNKNOWN) echo 0;;
    LOW) echo 1;;
    MEDIUM) echo 2;;
    HIGH) echo 3;;
    CRITICAL) echo 4;;
    *) echo 0;;
  esac
}

main() {
  parse_args "$@"
  check_bin grype
  local ref="oci:$OCI_PREFIX/$ORG/charts/rulehub-policies:$VERSION"
  echo "[vulns] Scanning $ref (threshold: $SEVERITY, allow: $ALLOW)"
  local out
  out=$(mktemp)
  trap 'rm -f "$out"' EXIT
  if ! grype -q -o json "$ref" > "$out" 2>/dev/null; then
    echo '[vulns] grype scan failed' >&2
    exit 2
  fi

  local count=0
  local threshold_rank shell_has_jq
  threshold_rank=$(rank_of "$SEVERITY")
  if command -v jq >/dev/null 2>&1; then
    shell_has_jq=1
    count=$(jq --arg sev "$SEVERITY" '
      def rank: {"NEGLIGIBLE":0,"UNKNOWN":0,"LOW":1,"MEDIUM":2,"HIGH":3,"CRITICAL":4};
      .matches | map(select(rank[.vulnerability.severity] >= rank[$sev])) | length' "$out")
  else
    shell_has_jq=0
    # Fallback: count only exact matches for chosen severity.
    count=$(grep -c '"severity":"'$SEVERITY'"' "$out" || true)
    if [[ "$SEVERITY" != "CRITICAL" ]]; then
      echo "[vulns] WARNING: jq absent; fallback counts only exact $SEVERITY (not >=). Install jq for accurate gating." >&2
    fi
  fi

  echo "[vulns] Findings >= $SEVERITY: $count (allow <= $ALLOW)"

  if (( LIST_TOP > 0 )); then
    if [[ $shell_has_jq -eq 1 ]]; then
      echo "[vulns] Top $LIST_TOP findings:" >&2
      jq --arg sev "$SEVERITY" --argjson top "$LIST_TOP" '
        def rank: {"NEGLIGIBLE":0,"UNKNOWN":0,"LOW":1,"MEDIUM":2,"HIGH":3,"CRITICAL":4};
        .matches
        | map(select(rank[.vulnerability.severity] >= rank[$sev]))
        | sort_by(.vulnerability.severity) | reverse
        | .[0:$top]
        | .[] | " - [" + .vulnerability.severity + "] " + .vulnerability.id + " -> " + (.artifact.name // "")' "$out" >&2
    else
      echo "[vulns] (jq not present; cannot list top findings)" >&2
    fi
  fi

  if (( count > ALLOW )); then
    echo "[vulns] FAIL: vulnerability threshold exceeded" >&2
    exit 1
  fi
  echo "[vulns] PASS: within allowed threshold"
}

main "$@"
