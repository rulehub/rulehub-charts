#!/usr/bin/env bash
set -euo pipefail
# Generate the Supported Kubernetes Versions section in README.md based on the helm-validate workflow matrix.
# Idempotent: rewrites only the block between markers.
# Markers: <!-- SUPPORTED_K8S_VERSIONS:START --> ... <!-- SUPPORTED_K8S_VERSIONS:END -->

WORKFLOW_FILE=".github/workflows/helm-validate.yml"
README_FILE="README.md"
START_MARK="<!-- SUPPORTED_K8S_VERSIONS:START -->"
END_MARK="<!-- SUPPORTED_K8S_VERSIONS:END -->"

if [[ ! -f "$WORKFLOW_FILE" ]]; then
  echo "Workflow file not found: $WORKFLOW_FILE" >&2
  exit 1
fi
if [[ ! -f "$README_FILE" ]]; then
  echo "README not found: $README_FILE" >&2
  exit 1
fi

# Extract kubeVersion arrays (unique versions)
VERSIONS=$(grep -E "kubeVersion: \[" "$WORKFLOW_FILE" | sed -E 's/.*kubeVersion: \[(.*)\].*/\1/' | tr -d '"' | tr ',' '\n' | sed 's/ //g' | sort -u)
if [[ -z "$VERSIONS" ]]; then
  echo "No versions found in workflow matrix" >&2
  exit 1
fi

TABLE_HEADER='| Version |\n|---------|'
TABLE_ROWS=""
while IFS= read -r ver; do
  [[ -z "$ver" ]] && continue
  TABLE_ROWS+="\n| $ver |"
done <<<"$VERSIONS"

NEW_BLOCK="${START_MARK}
Currently validated in CI against the following Kubernetes minor versions (matrix from \`.github/workflows/helm-validate.yml\`):\n\n${TABLE_HEADER}${TABLE_ROWS}\n\nNotes:\n* Chart templates are rendered & linted against all listed versions (helm template, kubeconform, kind create cluster, chart-testing install).\n* Policy resources (Gatekeeper & Kyverno) are designed to remain forward-compatible within the same minor; new Kubernetes API deprecations will be tracked and matrix adjusted accordingly.\n* Section maintained automatically via \`make k8s-versions-section\` (script: \`hack/gen-supported-k8s-versions.sh\`). Do not edit manually between markers.\n${END_MARK}"

# Replace existing block or append if missing
if grep -q "$START_MARK" "$README_FILE"; then
  # Use awk to keep everything outside the block and insert new block
  awk -v start="$START_MARK" -v end="$END_MARK" -v block="$NEW_BLOCK" '
    BEGIN{printed=0}
    $0 ~ start {print block; skip=1; next}
    $0 ~ end {skip=0; next}
    skip!=1 {print}
  ' "$README_FILE" >"${README_FILE}.tmp" && mv "${README_FILE}.tmp" "$README_FILE"
else
  printf "\n## Supported Kubernetes Versions (auto-generated)\n\n%s\n" "$NEW_BLOCK" >> "$README_FILE"
fi

echo "Updated Supported Kubernetes Versions section with versions:" >&2
printf "%s\n" "$VERSIONS" >&2
