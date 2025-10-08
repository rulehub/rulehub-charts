#!/usr/bin/env bash
set -euo pipefail

# compare-index.sh
# Usage: ./hack/drift/compare-index.sh path/to/index.json
# Compares rulehub core index.json (packages[].id) with local policy YAML annotations (rulehub.id)
# Outputs Added (present locally, missing in index) and Missing (in index, absent locally)
# Exits with non-zero code if drift detected unless DRIFT_ALLOW=true

INDEX_JSON=${1:-}
if [[ -z "${INDEX_JSON}" ]]; then
  echo "ERR: path to index.json required" >&2
  exit 2
fi
if [[ ! -f "${INDEX_JSON}" ]]; then
  echo "ERR: index.json not found: ${INDEX_JSON}" >&2
  exit 2
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Extract IDs from index.json
jq -r '.packages[]?.id' "${INDEX_JSON}" | sort -u >"${TMP_DIR}/index_ids.txt"

# Collect local rulehub.id annotations
find files -type f -name '*.yaml' -o -name '*.yml' | while read -r f; do
  # Grep annotation lines; tolerate quoted or unquoted values
  awk '/rulehub.id:/ {print $2}' "$f" | sed 's/"//g' | sed "s/'//g" || true
done | grep -v '^$' | sort -u >"${TMP_DIR}/local_ids.txt"

# Compute sets
comm -23 "${TMP_DIR}/local_ids.txt" "${TMP_DIR}/index_ids.txt" >"${TMP_DIR}/added.txt"   # present locally only
comm -13 "${TMP_DIR}/local_ids.txt" "${TMP_DIR}/index_ids.txt" >"${TMP_DIR}/missing.txt" # present in index only

ADDED_COUNT=$(wc -l <"${TMP_DIR}/added.txt")
MISSING_COUNT=$(wc -l <"${TMP_DIR}/missing.txt")

echo "== Drift Report =="
echo "Local only (Added relative to index): ${ADDED_COUNT}"
if [[ ${ADDED_COUNT} -gt 0 ]]; then
  cat "${TMP_DIR}/added.txt"
fi

echo "Index only (Missing locally): ${MISSING_COUNT}"
if [[ ${MISSING_COUNT} -gt 0 ]]; then
  cat "${TMP_DIR}/missing.txt"
fi

if [[ ${ADDED_COUNT} -eq 0 && ${MISSING_COUNT} -eq 0 ]]; then
  echo "No drift detected." >&2
  exit 0
fi

if [[ "${DRIFT_ALLOW:-false}" == "true" ]]; then
  echo "Drift detected but allowed by DRIFT_ALLOW=true" >&2
  exit 0
fi

echo "Drift detected." >&2
exit 1
