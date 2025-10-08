#!/usr/bin/env bash
set -euo pipefail
# Compare previously stored snapshot directory against freshly generated snapshots.
# Usage: hack/compare-snapshots.sh <baseline_dir> [values_file]
# Generates a temp current snapshot and runs diff. Exits non-zero on differences.

BASELINE_DIR="${1:-snapshots/baseline}"
VALUES_FILE="${2:-values.yaml}"
CURRENT_DIR="snapshots/current"

if [[ ! -d "$BASELINE_DIR" ]]; then
  echo "Baseline snapshot dir $BASELINE_DIR not found" >&2; exit 2; fi

# Generate current
hack/generate-snapshots.sh "$VALUES_FILE" "$CURRENT_DIR" >/dev/null

echo "Diff (baseline vs current):"
set +e
diff -ruN "$BASELINE_DIR" "$CURRENT_DIR" | sed 's/^/  /'
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo "Snapshot mismatch detected." >&2
  exit 1
fi

echo "Snapshots match baseline."
