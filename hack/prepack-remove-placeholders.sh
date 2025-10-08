#!/usr/bin/env bash
set -euo pipefail

# prepack-remove-placeholders.sh
# Purpose: Produce a packaged chart tarball that excludes placeholder policy YAML files.
# Rationale: Placeholder files ( *placeholder*.yaml ) are scaffolding artifacts useful during
# development but must not ship in release artifacts. This script creates an isolated copy of
# the chart, removes placeholders, optionally disables corresponding keys in values.yaml (without
# mutating the workspace), and runs `helm package`.
#
# Environment variables:
#   OUT_DIR    Directory to place the final packaged chart (default: dist)
#   WORK_DIR   Staging working directory (default: .pack)
#   CHART_DIR  Source chart directory (default: .)
#
# Usage:
#   hack/prepack-remove-placeholders.sh
# or via Make target:
#   make package-clean

OUT_DIR=${OUT_DIR:-dist}
WORK_DIR=${WORK_DIR:-.pack}
CHART_DIR=${CHART_DIR:-.}

echo "[prepack] Cleaning staging directories"
rm -rf "${WORK_DIR}" "${OUT_DIR}" >/dev/null 2>&1 || true
mkdir -p "${WORK_DIR}" "${OUT_DIR}"

echo "[prepack] Copying chart sources"
# Use rsync to preserve structure while excluding VCS + build dirs.
rsync -a --exclude '.git' --exclude '.pack' --exclude 'dist' "${CHART_DIR}/" "${WORK_DIR}/chart/"

STAGING_CHART="${WORK_DIR}/chart"

echo "[prepack] Searching for placeholder YAML files"
mapfile -t PLACEHOLDERS < <(find "${STAGING_CHART}/files" -type f -name '*placeholder*.yaml' 2>/dev/null || true)

if (( ${#PLACEHOLDERS[@]} > 0 )); then
  echo "[prepack] Removing placeholder files:" >&2
  for f in "${PLACEHOLDERS[@]}"; do
    echo "  - ${f#${STAGING_CHART}/}"
    rm -f "$f"
  done
else
  echo "[prepack] No placeholder files found"
fi

# Optionally, we can disable placeholder keys in values.yaml inside the staging chart so that
# if templates referenced them conditionally they remain false (defensive). We only modify the
# staging copy.
if grep -q 'placeholder' "${STAGING_CHART}/values.yaml"; then
  echo "[prepack] Disabling placeholder keys in values.yaml (staging only)"
  # For each key line that matches 'placeholder:' ensure the next 'enabled:' line becomes false.
  # This sed approach: when matching a line ending with 'placeholder:' set a flag, and when the
  # next enabled line is encountered with flag set, replace true->false then clear flag.
  sed -i '' -e '' 2>/dev/null || true # macOS compatibility (ignored in Linux)
  awk 'BEGIN{p=0} /placeholder:/{p=1; print; next} p==1 && /enabled:/{sub(/true/,"false"); p=0; print; next} {print}' \
    "${STAGING_CHART}/values.yaml" > "${STAGING_CHART}/values.yaml.tmp" && mv "${STAGING_CHART}/values.yaml.tmp" "${STAGING_CHART}/values.yaml"
fi

echo "[prepack] Packaging cleaned chart"
helm package "${STAGING_CHART}" -d "${OUT_DIR}" >/dev/null

echo "[prepack] Done. Artifacts in ${OUT_DIR}:"
ls -1 "${OUT_DIR}" | sed 's/^/  - /'
