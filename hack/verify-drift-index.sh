#!/usr/bin/env bash
set -euo pipefail

# verify-drift-index.sh
# Wrapper around hack/drift/compare-index.sh adding discovery & ergonomics.
# Usage: hack/verify-drift-index.sh [--allow-drift] [INDEX_JSON]
#   --allow-drift : do not fail (exit 0) even if drift detected (sets DRIFT_ALLOW=true)
# INDEX_JSON      : path to core index.json (packages[].id); can also be supplied via CORE_INDEX env var
# Auto-discovery: if not provided, tries ./hack/drift/index.json then ../core/dist/index.json

ALLOW=false
ARGS=()
for a in "$@"; do
  case "$a" in
    --allow-drift) ALLOW=true ;;
    *) ARGS+=("$a") ;;
  esac
done
set -- "${ARGS[@]}"

INDEX_JSON="${1:-${CORE_INDEX:-}}"

if [[ -z "$INDEX_JSON" ]]; then
  for cand in "hack/drift/index.json" "../core/dist/index.json"; do
    if [[ -f "$cand" ]]; then INDEX_JSON="$cand"; break; fi
  done
fi

if [[ -z "$INDEX_JSON" ]]; then
  echo "ERR: index.json path not provided and auto-discovery failed." >&2
  echo "Provide path explicitly: hack/verify-drift-index.sh /path/to/index.json" >&2
  exit 2
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
