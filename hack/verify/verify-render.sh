#!/usr/bin/env bash
set -euo pipefail
# Verifies that rendered manifests don't contain metadata.name with underscores (_)
# Renders a minimal template (full values) and greps for 'metadata:' name lines.
# Fails if any name contains '_'.

CHART_DIR="${1:-.}"
TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

helm template rulehub "$CHART_DIR" --values values.yaml > "$TMP_FILE"
# Extract name lines
if grep -E '^  name:.*_' "$TMP_FILE" >/dev/null; then
  echo "Found metadata.name with underscore (_):" >&2
  grep -nE '^  name:.*_' "$TMP_FILE" >&2
  echo "Underscores are not allowed in Kubernetes resource names. Rename before committing." >&2
  exit 1
fi

echo "Render verification passed (no underscores in metadata.name)."
