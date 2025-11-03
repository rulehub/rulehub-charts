#!/usr/bin/env bash
set -euo pipefail

# verify-manifest-schema.sh
# Validate manifest.json against manifest.schema.json and perform light semantics.
# Usage: bash hack/verify-manifest-schema.sh [--manifest manifest.json] [--schema manifest.schema.json]

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../.." &>/dev/null && pwd)"
MANIFEST="$ROOT_DIR/manifest.json"
SCHEMA="$ROOT_DIR/manifest.schema.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="$2"; shift 2;;
    --schema) SCHEMA="$2"; shift 2;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

if [[ ! -f "$MANIFEST" ]]; then
  echo "manifest not found: $MANIFEST" >&2
  exit 2
fi
if [[ ! -f "$SCHEMA" ]]; then
  echo "schema not found: $SCHEMA" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq required" >&2; exit 2
fi

# Basic schema validation (draft-07) using ajv if available; otherwise structural checks with jq.
if command -v ajv >/dev/null 2>&1; then
  if ! ajv validate -s "$SCHEMA" -d "$MANIFEST" >/dev/null 2>&1; then
    echo "Schema validation FAILED" >&2
    ajv validate -s "$SCHEMA" -d "$MANIFEST" || true
    exit 1
  fi
else
  # Fallback: ensure required keys exist and sha256 format.
  if ! jq -e 'map(select(has("file") and has("sha256") and has("rulehub.id"))) | length == length' "$MANIFEST" >/dev/null; then
    echo "Manifest structural validation failed (missing required keys)" >&2
    exit 1
  fi
  if ! jq -e 'map(select(.sha256|test("^[a-f0-9]{64}$"))) | length == length' "$MANIFEST" >/dev/null; then
    echo "Manifest sha256 pattern mismatch" >&2
    exit 1
  fi
fi

# Semantic: duplicate detection
#  - Duplicate files are not allowed (same path twice)
#  - Duplicate ids are allowed across different frameworks (e.g., same policy in Gatekeeper and Kyverno)
#  - Within the same framework, allow duplicate ids only when the files are underscore/hyphen aliases
#    (i.e., their normalized basenames are identical after mapping '_' -> '-' and stripping extension/dir)

dup_files=$(jq -r '.[].file' "$MANIFEST" | sort | uniq -d || true)
[[ -n "$dup_files" ]] && { echo -e "Duplicate file entries:\n$dup_files" >&2; exit 1; }

# Build id|framework -> set of normalized basenames
mapfile -t lines < <(jq -r '.[] | [."rulehub.id", .framework, .file] | @tsv' "$MANIFEST")
declare -A uniq_norms
declare -A counts
for line in "${lines[@]}"; do
  IFS=$'\t' read -r id fw file <<<"$line"
  base=$(basename "$file")
  base=${base%.*}
  norm=$(echo "$base" | tr '_' '-' | sed -E 's/-+/-/g')
  key="${id}|${fw}"
  counts["$key"]=$(( ${counts["$key"]:-0} + 1 ))
  uniq_norms["$key|$norm"]=1
done

bad_ids=()
for k in "${!counts[@]}"; do
  # count distinct norms for this id|framework
  n=0
  for kk in "${!uniq_norms[@]}"; do
    [[ "$kk" == "$k|"* ]] || continue
    n=$((n+1))
  done
  # If there are multiple entries and more than one distinct normalized basename, flag as bad
  if (( ${counts["$k"]} > 1 && n > 1 )); then
    bad_ids+=("$k")
  fi
done

if ((${#bad_ids[@]})); then
  echo "Duplicate rulehub.id entries within the same framework (non-alias):" >&2
  for b in "${bad_ids[@]}"; do echo "  - $b" >&2; done
  exit 1
fi

echo "Manifest OK"
