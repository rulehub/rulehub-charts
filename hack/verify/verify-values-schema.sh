#!/usr/bin/env bash
set -euo pipefail

# verify-values-schema.sh
#
# Purpose:
#   Validate that chart values conform to values.schema.json using Helm's
#   built-in schema validation (helm lint + a dry-run template render).
#   Fails (non-zero exit) if schema violations are detected.
#
# Behavior:
#   1. Runs 'helm lint .' (which performs schema validation).
#   2. Performs 'helm template .' to ensure no runtime schema / rendering errors.
#   3. Prints a success message if both steps pass.
#
# Notes:
#   - Assumes execution from repository root (or provide path via CHART_DIR env var).
#   - No network access / dependencies expected (single chart repo).
#
CHART_DIR="${CHART_DIR:-.}"

echo "[verify-values-schema] Helm lint..." >&2
helm lint "$CHART_DIR" 1>&2

echo "[verify-values-schema] Helm template (schema + render)..." >&2
helm template "$CHART_DIR" >/dev/null

echo "[verify-values-schema] OK: values conform to schema." >&2
