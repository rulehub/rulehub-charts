#!/usr/bin/env bash
set -euo pipefail

# Verify that dist/index.json is up-to-date and structurally valid for the Backstage plugin

# NOTE: this script lives in hack/verify/, so repo root is two levels up
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_FILE="${ROOT_DIR}/dist/index.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 1
fi

if [[ ! -f "${OUT_FILE}" ]]; then
  echo "dist/index.json missing; run hack/gen/gen-plugin-index.sh" >&2
  exit 2
fi

# Regenerate to ensure current content (call via bash to avoid exec-bit issues)
bash "${ROOT_DIR}/hack/gen/gen-plugin-index.sh"

# Basic shape checks
jq -e '.packages and (.packages | type == "array")' "${OUT_FILE}" >/dev/null

# Ensure each package has id and name and at least one of repoPath/kyvernoPath/gatekeeperPath
MISSING=$(jq -r '
  .packages[] | select((.id|not) or (.name|not) or ((.repoPath|not) and (.kyvernoPath|not) and (.gatekeeperPath|not))) | .id // "<unknown>"' "${OUT_FILE}")
if [[ -n "${MISSING}" ]]; then
  echo "ERROR: some packages missing required fields or links:" >&2
  echo "${MISSING}" >&2
  exit 3
fi

echo "plugin index verified"
