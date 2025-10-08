#!/usr/bin/env bash
set -euo pipefail

# Verify that dist/index.json is up-to-date and structurally valid for the Backstage plugin

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="${ROOT_DIR}/manifest.json"
OUT_FILE="${ROOT_DIR}/dist/index.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 1
fi

if [[ ! -f "${OUT_FILE}" ]]; then
  echo "dist/index.json missing; run hack/generate-plugin-index.sh" >&2
  exit 2
fi

# Regenerate to a temp and diff (call via bash to avoid exec-bit issues)
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
bash "${ROOT_DIR}/hack/generate-plugin-index.sh"

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
