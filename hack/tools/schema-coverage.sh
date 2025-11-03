#!/usr/bin/env bash
set -euo pipefail

# schema-coverage.sh
# Estimate coverage of values.yaml keys by values.schema.json (top-level & nested first-level policy maps).
# Heuristic: counts distinct dotted key paths present in values.yaml and how many have a schema definition.
# Outputs summary percentage and lists missing.
# Usage: bash hack/schema-coverage.sh [--values values.yaml] [--schema values.schema.json]

VALUES=values.yaml
SCHEMA=values.schema.json

while [[ $# -gt 0 ]]; do
  case "$1" in
    --values) VALUES="$2"; shift 2;;
    --schema) SCHEMA="$2"; shift 2;;
    -h|--help) grep '^# ' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

command -v yq >/dev/null 2>&1 || { echo 'Requires yq (v4) in PATH' >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo 'Requires jq in PATH' >&2; exit 2; }

# Collect schema keys by recursively traversing "properties" and emitting dotted prefixes
SCHEMA_KEYS=$(jq -r '
  def walk_props($obj; $prefix):
    (($obj.properties // {}) | to_entries[]) as $e
    | (($prefix + [$e.key]) | join("."))
    , walk_props($e.value; $prefix + [$e.key]);
  walk_props(. ; [])
' "$SCHEMA" | sort -u)

# Collect values keys (dotted) using jq over JSON to avoid yq expr incompatibilities
VALUES_KEYS=$(yq eval -o=json '.' "$VALUES" | jq -r 'paths | map(tostring) | join(".")' | sort -u)

total=0; covered=0
missing=()

while IFS= read -r k; do
  [[ -z "$k" ]] && continue
  # Skip scalar booleans for individual policy toggles (gatekeeper.policies.X.enabled already implied by schema additionalProperties)
  if [[ "$k" == gatekeeper.policies.*.* ]] || [[ "$k" == kyverno.policies.*.* ]]; then
    # treat only the .enabled and .validationFailureAction keys as coverage targets
    if [[ "$k" != *.enabled && "$k" != *.validationFailureAction ]]; then
      continue
    fi
  fi
  total=$((total+1))
  # Check if any schema key is a prefix of value key (exact or followed by a dot)
  found=0
  while IFS= read -r sk; do
    [[ -z "$sk" ]] && continue
    if [[ "$k" == "$sk" || "$k" == "$sk".* ]]; then
      found=1
      break
    fi
  done < <(echo "$SCHEMA_KEYS")
  if (( found )); then
    covered=$((covered+1))
  else
    missing+=("$k")
  fi
done < <(echo "$VALUES_KEYS")

percent=0
if (( total > 0 )); then
  percent=$(( 100 * covered / total ))
fi

echo "Schema coverage: ${covered}/${total} (${percent}%)"
if ((${#missing[@]})); then
  echo 'Missing definitions:'
  printf '  - %s\n' "${missing[@]}"
else
  echo 'No missing keys detected by heuristic.'
fi
