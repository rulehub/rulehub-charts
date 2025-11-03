#!/usr/bin/env bash
set -euo pipefail

# verify-dual-engine-coverage.sh
# Verify that every rulehub.id present in manifest.json has BOTH engines packaged:
#  - at least one Kyverno entry (framework=="kyverno")
#  - at least one Gatekeeper entry (framework=="gatekeeper" or "gatekeeper-template")
#
# Exit codes:
#  0 - OK (all IDs have both engines) or allowed via --allow
#  1 - Missing coverage detected (and not allowed)
#  2 - Usage / environment error
#
# Usage:
#   hack/verify-dual-engine-coverage.sh [--allow]

ALLOW=false
for a in "$@"; do
  case "$a" in
    --allow) ALLOW=true ;;
    -h|--help)
      echo "Usage: $0 [--allow]"; exit 0 ;;
    *) echo "Unknown arg: $a" >&2; exit 2 ;;
  esac
done

# Resolve repository root (this script lives in hack/verify)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../.." &>/dev/null && pwd)"
MANIFEST="$ROOT_DIR/manifest.json"

if [[ ! -f "$MANIFEST" ]]; then
  echo "ERR: manifest.json not found at $MANIFEST" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "ERR: jq required" >&2
  exit 2
fi

# Build a coverage table: id,hasKyverno,hasGK, then filter out placeholders/templates
coverage_json="$(jq -c '
  sort_by(."rulehub.id")
  | group_by(."rulehub.id")
  | map({
      id: .[0]."rulehub.id",
      hasKyverno: (any(.[]; .framework == "kyverno")),
      hasGK: (any(.[]; (.framework == "gatekeeper" or .framework == "gatekeeper-template")))
    })
  | map(select(
      # Exclude placeholder/template ids from gating
      (.id | test("placeholder"; "i") | not)
      and (.id | endswith(".template") | not)
    ))
' "$MANIFEST")"

missing_list="$(printf '%s\n' "$coverage_json" | jq -r '.[] | select((.hasKyverno|not) or (.hasGK|not)) | "\(.id)\tkyverno=\(.hasKyverno)\tgatekeeper=\(.hasGK)"')"
missing_count=$(printf '%s\n' "$missing_list" | grep -c . || true)
total_ids=$(printf '%s\n' "$coverage_json" | jq -r 'length')

echo "== Dual-Engine Coverage Report =="
echo "Total IDs: ${total_ids}"
echo "Missing either engine: ${missing_count}"
if [[ "$missing_count" -gt 0 ]]; then
  echo "-- IDs missing coverage --"
  printf '%s\n' "$missing_list"
fi

if [[ "$missing_count" -eq 0 ]]; then
  echo "All IDs have both Kyverno and Gatekeeper coverage."
  exit 0
fi

if $ALLOW; then
  echo "Missing coverage detected but allowed via --allow" >&2
  exit 0
fi

echo "Dual-engine coverage requirement FAILED" >&2
exit 1
