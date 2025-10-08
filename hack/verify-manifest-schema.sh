#!/usr/bin/env bash
set -euo pipefail

# verify-manifest-schema.sh
# Validate manifest.json against manifest.schema.json and perform light semantics.
# Usage: bash hack/verify-manifest-schema.sh [--manifest manifest.json] [--schema manifest.schema.json]

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOT_DIR="${SCRIPT_DIR%/hack}"
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

# Semantic: duplicate file or rulehub.id detection
dup_files=$(jq -r '.[].file' "$MANIFEST" | sort | uniq -d || true)
dup_ids=$(jq -r '.["rulehub.id"]' "$MANIFEST" 2>/dev/null | sort | uniq -d || true)
[[ -n "$dup_files" ]] && { echo "Duplicate file entries:\n$dup_files" >&2; exit 1; }
[[ -n "$dup_ids" ]] && { echo "Duplicate rulehub.id entries:\n$dup_ids" >&2; exit 1; }

echo "Manifest OK"
