#!/usr/bin/env bash
set -euo pipefail

# Generates VALUES_TABLE.md from values.yaml & values.schema.json (basic types only)
# Limitations: descriptions missing in schema will be '-'.

VALUES_FILE="values.yaml"
SCHEMA_FILE="values.schema.json"
OUT_FILE="VALUES_TABLE.md"
# Write to a temp file first, then replace only if content changed (idempotent output & clearer logs)
TMP_OUT="$(mktemp)"
cleanup() { rm -f "$TMP_OUT"; }
trap cleanup EXIT

if [[ ! -f $VALUES_FILE ]]; then
  echo "values.yaml not found" >&2; exit 1; fi
if [[ ! -f $SCHEMA_FILE ]]; then
  echo "values.schema.json not found" >&2; exit 1; fi

echo "# Values Reference Table (Generated)" > "$TMP_OUT"
echo >> "$TMP_OUT"
echo '> Regenerate via `make values-table`. Descriptions need schema enrichment.' >> "$TMP_OUT"
echo >> "$TMP_OUT"
echo '| Key | Type | Default | Description |' >> "$TMP_OUT"
echo '|-----|------|---------|-------------|' >> "$TMP_OUT"

# Top-level keys types (simple extraction)
gatekeeper_enabled_default="$(grep -E '^gatekeeper:' -A3 values.yaml | grep 'enabled:' | head -1 | awk '{print $2}')"
kyverno_enabled_default="$(grep -E '^kyverno:' -A5 values.yaml | grep 'enabled:' | head -1 | awk '{print $2}')"
kyverno_vfa_default="$(grep -E '^kyverno:' -A12 values.yaml | grep 'validationFailureAction:' | head -1 | awk '{print $2}')"

printf '| %s | %s | %s | %s |\n' 'gatekeeper.enabled' 'boolean' "${gatekeeper_enabled_default:-true}" 'Enable Gatekeeper engine' >> "$TMP_OUT"
printf '| %s | %s | %s | %s |\n' 'kyverno.enabled' 'boolean' "${kyverno_enabled_default:-true}" 'Enable Kyverno engine' >> "$TMP_OUT"
printf '| %s | %s | %s | %s |\n' 'kyverno.validationFailureAction' 'string' "${kyverno_vfa_default:-}" 'Global Kyverno override ("", audit, enforce)' >> "$TMP_OUT"

# Policies: extract lists deterministically without external yq dependency (awk-only)
awk '
BEGIN{sect=""; subsect=""}
# Top-level keys
/^[^[:space:]]/ {
  if ($0 ~ /^gatekeeper:/) { sect="g"; subsect=""; next }
  if ($0 ~ /^kyverno:/) { sect="k"; subsect=""; next }
  # Any other top-level key: leave sections
  sect=""; subsect=""; next
}
# Two-space indent keys under current section
/^  [^[:space:]]/ {
  if (sect=="g" && $0 ~ /^  policies:/) { subsect="gp"; next }
  if (sect=="k" && $0 ~ /^  policies:/) { subsect="kp"; next }
  # Different two-space key under gatekeeper/kyverno ends policies block
  if (subsect!="") { subsect="" }
  next
}
# Four-space indent: collect policy names only within policies block
(subsect=="gp" || subsect=="kp") && /^    [a-zA-Z0-9_.-]+:/ {
  key=$1; sub(/:$/,"",key);
  if(subsect=="gp") print "G " key; else print "K " key;
}
' values.yaml | while read -r kind name; do
  if [[ $kind == G ]]; then
    printf '| gatekeeper.policies.%s.enabled | boolean | true | - |\n' "$name" >> "$TMP_OUT"
  else
    printf '| kyverno.policies.%s.enabled | boolean | true | - |\n' "$name" >> "$TMP_OUT"
  fi
done

echo >> "$TMP_OUT"
echo "*Generated automatically - do not edit manually*" >> "$TMP_OUT"

# Replace only if changed; keep timestamp stable when no diff
if [[ -f "$OUT_FILE" ]] && cmp -s "$TMP_OUT" "$OUT_FILE"; then
  echo "No changes to $OUT_FILE"
else
  mv "$TMP_OUT" "$OUT_FILE"
  # disable trap from removing the moved file
  trap - EXIT
  echo "Updated $OUT_FILE"
fi
