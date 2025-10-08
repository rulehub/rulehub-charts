#!/usr/bin/env bash
set -euo pipefail
# Verify that values.yaml contains schemaVersion matching values.schema.json const.
# Usage: hack/verify-schema-version.sh [--quiet]
QUIET=0
if [[ ${1:-} == "--quiet" ]]; then QUIET=1; fi
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
values_file="$root_dir/values.yaml"
schema_file="$root_dir/values.schema.json"
if ! command -v yq >/dev/null 2>&1; then echo "yq required" >&2; exit 2; fi
if ! command -v jq >/dev/null 2>&1; then echo "jq required" >&2; exit 2; fi
val_version=$(yq '.schemaVersion // ""' "$values_file")
schema_const=$(jq -r '.properties.schemaVersion.const // empty' "$schema_file")
if [[ -z "$schema_const" ]]; then
  echo "Schema does not declare properties.schemaVersion.const" >&2
  exit 1
fi
if [[ "$val_version" != "$schema_const" ]]; then
  echo "schemaVersion mismatch: values.yaml=$val_version schema=$schema_const" >&2
  exit 1
fi
if [[ $QUIET -eq 0 ]]; then
  echo "schemaVersion OK ($schema_const)"
fi
