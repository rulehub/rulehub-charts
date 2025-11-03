#!/usr/bin/env bash
set -euo pipefail

# Generate a markdown table of policies with columns:
# policy key | framework | enforce? | description
# Output file: VALUES_TABLE.md (appends / replaces section)
# Description derived from annotation rulehub.title (if placeholder or missing -> '-')
# Enforce? determined for Kyverno from spec.validationFailureAction == enforce OR
#   per-policy override in values.yaml (kyverno.policies.<name>.validationFailureAction) if present.
# For Gatekeeper, always '-' (no direct enforce level concept in Constraints; admission deny implied when installed).

VALUES_FILE="values.yaml"
OUT_FILE="VALUES_TABLE.md"

if [[ ! -f $VALUES_FILE ]]; then echo "values.yaml missing" >&2; exit 1; fi

tmp=$(mktemp)

echo '# Policy Table (Generated)' >"$tmp"
echo >>"$tmp"
echo '| Policy Key | Framework | Enforce? | Description |' >>"$tmp"
echo '|------------|-----------|----------|-------------|' >>"$tmp"

# Build associative arrays for per-policy override (Kyverno) from values.yaml
declare -A KYVERNO_OVERRIDES
awk 'BEGIN{inpol=0} /^kyverno:/ {inK=1} inK && /^  policies:/ {inpol=1; next} inpol && /^[ ]{4}[a-zA-Z0-9_.-]+:/ {gsub(/^[ ]+/,"",$1); gsub(/:$/,"",$1); current=$1} inpol && /validationFailureAction:/ {gsub(/^[ ]+/,"",$1); v=$2; sub(/#.*/,"",v); printf "%s %s\n", current, v }' "$VALUES_FILE" | while read -r key val; do
  KYVERNO_OVERRIDES[$key]="$val"
done

# Function: extract rulehub.title from a file
extract_title() {
  local f="$1"
  local t
  t=$(grep -E 'rulehub.title:' "$f" | head -1 | sed -E 's/.*rulehub.title:[ ]*//') || true
  if [[ -z $t || $t == '<Policy'\ * ]]; then echo '-'; else echo "$t"; fi
}

# Kyverno policies
for f in files/kyverno/*.yaml; do
  [ -e "$f" ] || continue
  name=$(basename "$f" .yaml)
  # Detect enforce from file
  enforce='-' # default unknown
  if grep -q 'validationFailureAction: enforce' "$f"; then enforce='enforce'; else enforce='audit'; fi
  # Override if values.yaml specifies
  if [[ -n ${KYVERNO_OVERRIDES[$name]:-} ]]; then
    ov=${KYVERNO_OVERRIDES[$name]}
    if [[ $ov == 'enforce' || $ov == 'audit' ]]; then enforce="$ov"; fi
  fi
  title=$(extract_title "$f")
  echo "| $name | kyverno | $enforce | $title |" >>"$tmp"
done

# Gatekeeper constraints
for f in files/gatekeeper/*.yaml; do
  [ -e "$f" ] || continue
  name=$(basename "$f" .yaml)
  title=$(extract_title "$f")
  echo "| $name | gatekeeper | - | $title |" >>"$tmp"
done

mv "$tmp" "$OUT_FILE"
echo "Updated $OUT_FILE (policy table)"
