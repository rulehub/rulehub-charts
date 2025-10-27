#!/usr/bin/env bash
set -euo pipefail

# verify-drift-index.sh
# Wrapper around hack/drift/compare-index.sh adding discovery & ergonomics.
# Usage: hack/verify-drift-index.sh [--allow-drift] [INDEX_JSON]
#   --allow-drift : do not fail (exit 0) even if drift detected (sets DRIFT_ALLOW=true)
# INDEX_JSON      : path or URL (http/https) to core index.json (packages[].id);
#                   can also be supplied via CORE_INDEX or INDEX_JSON env var
# Auto-discovery: if not provided, tries ./hack/drift/index.json then ../core/dist/index.json
# Default fallback: https://rulehub.github.io/rulehub/plugin-index/index.json

ALLOW=false
ARGS=()
for a in "$@"; do
  case "$a" in
    --allow-drift) ALLOW=true ;;
    *) ARGS+=("$a") ;;
  esac
done
set -- "${ARGS[@]}"

INDEX_JSON="${1:-${INDEX_JSON:-${CORE_INDEX:-}}}"

if [[ -z "$INDEX_JSON" ]]; then
  for cand in "hack/drift/index.json" "../core/dist/index.json"; do
    if [[ -f "$cand" ]]; then INDEX_JSON="$cand"; break; fi
  done
fi

if [[ -z "$INDEX_JSON" ]]; then
  # Use stable published URL by default
  INDEX_JSON="https://rulehub.github.io/rulehub/plugin-index/index.json"
  echo "[verify-drift-index] Using default INDEX_JSON URL: $INDEX_JSON" >&2
fi

# If INDEX_JSON is a URL, download to a temporary file
TMP_DL=""
if [[ "$INDEX_JSON" =~ ^https?:// ]]; then
  if ! command -v curl >/dev/null 2>&1; then
    echo "ERR: curl is required to fetch index.json from URL: $INDEX_JSON" >&2
    exit 2
  fi
  TMP_DL="$(mktemp)" || TMP_DL="/tmp/rulehub-index.json"
  if ! curl -fsSL "$INDEX_JSON" -o "$TMP_DL"; then
    echo "ERR: failed to download index.json from URL: $INDEX_JSON" >&2
    exit 2
  fi
  # Basic sanity: ensure it's JSON
  if ! jq -e . >/dev/null 2>&1 <"$TMP_DL"; then
    echo "ERR: downloaded index.json is not valid JSON from: $INDEX_JSON" >&2
    rm -f "$TMP_DL" || true
    exit 2
  fi
  trap '[[ -n "$TMP_DL" ]] && rm -f "$TMP_DL" || true' EXIT
  INDEX_JSON="$TMP_DL"
fi

if [[ ! -f "$INDEX_JSON" ]]; then
  echo "ERR: index.json not found at: $INDEX_JSON" >&2
  exit 2
fi

if $ALLOW; then
  DRIFT_ALLOW=true bash hack/drift/compare-index.sh "$INDEX_JSON"
else
  bash hack/drift/compare-index.sh "$INDEX_JSON"
fi
