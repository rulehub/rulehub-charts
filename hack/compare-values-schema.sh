#!/usr/bin/env bash
set -euo pipefail
# Compare values.yaml keys vs values.schema.json definitions.
# Reports:
#  - keys present in values.yaml but missing in schema (top-level and policy maps)
#  - schema properties not present in values.yaml (excluding optional ones with empty maps)
#  - count of policy entries vs schema pattern (only generic additionalProperties today)
#  - any gatekeeper/kyverno policy key lacking a corresponding file in files/ dirs (lightweight cross-check)
# Limitations: does not fully expand all nested objects beyond known structure.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALUES="$ROOT_DIR/values.yaml"
SCHEMA="$ROOT_DIR/values.schema.json"

if ! command -v yq >/dev/null 2>&1; then
  echo "ERROR: yq is required (install e.g. 'pipx install yq' or 'brew install yq')." >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required." >&2
  exit 1
fi

# Extract top-level keys from values.yaml
values_top_keys=$(yq 'keys | .[]' "$VALUES")
# Extract schema top-level properties
schema_top_keys=$(jq -r '.properties | keys[]' "$SCHEMA")

missing_in_schema=()
for k in $values_top_keys; do
  if ! grep -qx "$k" <(echo "$schema_top_keys"); then
    missing_in_schema+=("$k")
  fi
done

missing_in_values=()
for k in $schema_top_keys; do
  if ! grep -qx "$k" <(echo "$values_top_keys"); then
    missing_in_values+=("$k")
  fi
done

echo "== Top-level key comparison =="
if ((${#missing_in_schema[@]})); then
  echo "Keys in values.yaml but absent in schema: ${missing_in_schema[*]}"
else
  echo "No extra top-level keys in values.yaml"
fi
if ((${#missing_in_values[@]})); then
  echo "Schema defines keys missing in values.yaml: ${missing_in_values[*]}"
else
  echo "No schema-only top-level keys"
fi

echo
# Policy keys
gk_policy_keys=$(yq '.gatekeeper.policies | keys | .[]' "$VALUES" 2>/dev/null || true)
kv_policy_keys=$(yq '.kyverno.policies | keys | .[]' "$VALUES" 2>/dev/null || true)

echo "Gatekeeper policy count: $(echo "$gk_policy_keys" | grep -c . || echo 0)"
echo "Kyverno policy count: $(echo "$kv_policy_keys" | grep -c . || echo 0)"

# Check that each policy map entry has required 'enabled' boolean
violations=()
while read -r pk; do
  [ -z "$pk" ] && continue
  enabled_val=$(yq -r ".gatekeeper.policies.[\"$pk\"].enabled" "$VALUES" 2>/dev/null || echo null)
  if [[ "$enabled_val" == "null" ]]; then
    violations+=("gatekeeper:$pk missing enabled")
  fi
done < <(echo "$gk_policy_keys")
while read -r pk; do
  [ -z "$pk" ] && continue
  enabled_val=$(yq -r ".kyverno.policies.[\"$pk\"].enabled" "$VALUES" 2>/dev/null || echo null)
  if [[ "$enabled_val" == "null" ]]; then
    violations+=("kyverno:$pk missing enabled")
  fi
done < <(echo "$kv_policy_keys")

if ((${#violations[@]})); then
  echo "Missing required 'enabled' field for entries:" >&2
  for v in "${violations[@]}"; do echo "  - $v" >&2; done
  exit_code=1
else
  echo "All policy entries declare 'enabled'."
  exit_code=0
fi

echo
# Lightweight file existence cross-check
missing_files=()
for pk in $gk_policy_keys; do
  if ! ls "$ROOT_DIR/files/gatekeeper/$pk"*.yaml >/dev/null 2>&1; then
    missing_files+=("gatekeeper:$pk")
  fi
done
for pk in $kv_policy_keys; do
  if ! ls "$ROOT_DIR/files/kyverno/$pk"*.yaml >/dev/null 2>&1; then
    missing_files+=("kyverno:$pk")
  fi
done
if ((${#missing_files[@]})); then
  echo "Policy keys without matching file prefix:" >&2
  for m in "${missing_files[@]}"; do echo "  - $m" >&2; done
else
  echo "All policy keys have at least one matching file prefix."
fi

# Describe any schema enums mismatches (currently only kyverno.validationFailureAction)
# Use jq index() to robustly handle empty string values present in enum
actual_global=$(yq -r '.kyverno.validationFailureAction // ""' "$VALUES" 2>/dev/null || echo '')
if ! jq -e --arg val "$actual_global" '.properties.kyverno.properties.validationFailureAction.enum | index($val)' "$SCHEMA" >/dev/null; then
  allowed_enum_str=$(jq -r '.properties.kyverno.properties.validationFailureAction.enum[]' "$SCHEMA" | tr '\n' ' ')
  echo "Global kyverno.validationFailureAction '$actual_global' not allowed by schema enum: $allowed_enum_str" >&2
  exit_code=1
else
  echo "Global kyverno.validationFailureAction within allowed enum."
fi

exit $exit_code
