#!/usr/bin/env bash
# verify-deterministic.sh
# Check that two consecutive helm template runs produce identical sha256.
# Usage: hack/verify-deterministic.sh [VALUES_FILE]
set -euo pipefail
CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VALUES_FILE="${1:-$CHART_DIR/values.yaml}"
TMP1=$(mktemp)
TMP2=$(mktemp)
trap 'rm -f "$TMP1" "$TMP2"' EXIT
normalize() {
  # Remove potentially non-deterministic lines (reserved for future use)
  # Currently passthrough, left for extension: e.g. add | grep -v 'generatedAt:' and similar.
  cat
}
helm template rulehub-policies "$CHART_DIR" -f "$VALUES_FILE" | normalize > "$TMP1"
helm template rulehub-policies "$CHART_DIR" -f "$VALUES_FILE" | normalize > "$TMP2"
H1=$(sha256sum "$TMP1" | awk '{print $1}')
H2=$(sha256sum "$TMP2" | awk '{print $1}')
if [[ "$H1" != "$H2" ]]; then
  echo "Determinism check FAILED: $H1 != $H2" >&2
  diff -u "$TMP1" "$TMP2" || true
  exit 1
fi
echo "Determinism OK ($H1)" >&2
