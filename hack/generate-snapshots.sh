#!/usr/bin/env bash
set -euo pipefail
# Generate golden snapshot YAML manifests for template regression testing.
# Usage: hack/generate-snapshots.sh [VALUES_FILE] [OUT_DIR]
# Default VALUES_FILE=values.yaml OUT_DIR=snapshots/current
# Process:
#  1. helm template with sorted output (one big file)
#  2. Split into individual documents named NN-kind-metadata.name.yaml for stability
#  3. Strip volatile fields (creationTimestamp, annotations with build timestamps)
#  4. Normalize ordering (yq sorting keys) if yq is available

VALUES_FILE="${1:-values.yaml}"
OUT_DIR="${2:-snapshots/current}"
CHART_DIR="${CHART_DIR:-.}"

if ! command -v helm >/dev/null 2>&1; then
  echo "helm not found" >&2; exit 1; fi

mkdir -p "$OUT_DIR"
TMP_ALL=$(mktemp)
trap 'rm -f "$TMP_ALL"' EXIT

helm template rulehub "$CHART_DIR" --values "$VALUES_FILE" > "$TMP_ALL"
# Split
awk 'BEGIN{n=0;file=""} /^---/ {next} /^apiVersion:/ {n++; file=sprintf("%s/%03d.yaml","'$OUT_DIR'", n)} {print >> file}' "$TMP_ALL"

# Post-process each file
idx=0
for f in "$OUT_DIR"/*.yaml; do
  # Extract kind and name
  kind=$(grep '^kind:' "$f" | head -1 | awk '{print $2}') || kind=Unknown
  name=$(grep '^  name:' "$f" | head -1 | awk '{print $2}') || name=noname
  newf="${OUT_DIR}/$(printf '%03d' $((++idx)))-${kind}-${name}.yaml"
  # Clean unstable fields; requires sed
  sed -E '/creationTimestamp:/d' "$f" > "$newf.tmp"
  # Optional normalization with yq
  if command -v yq >/dev/null 2>&1; then
    yq eval '... style=""' "$newf.tmp" > "$newf"
  else
    mv "$newf.tmp" "$newf"
  fi
  rm -f "$f" "$newf.tmp" 2>/dev/null || true
  echo "$newf" | sed 's#.*/##' >> "$OUT_DIR/_index.txt"

done

echo "Generated $(wc -l < "$OUT_DIR/_index.txt") snapshot docs in $OUT_DIR"

# Generate per-file hashes for golden comparison
if command -v sha256sum >/dev/null 2>&1; then
  bash "$(dirname "$0")/generate-snapshot-hashes.sh" "$OUT_DIR" >/dev/null
  echo "Hashes file: $OUT_DIR/hashes.txt"
fi
