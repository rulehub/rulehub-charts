#!/usr/bin/env bash
# verify-enforce-rationale.sh
# Fails if any Kyverno policy with effective validationFailureAction=enforce
# lacks a rationale comment in values.yaml under its policy key.
#
# Portable on macOS bash 3.2 (no associative arrays).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VALUES_FILE="$ROOT_DIR/values.yaml"

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "values.yaml not found" >&2
  exit 2
fi

# Collect enforced policy keys into a temp file (one per line)
ENFORCE_FILE="$(mktemp)"; trap 'rm -f "$ENFORCE_FILE"' EXIT

# a) From source files
grep -l 'validationFailureAction: enforce' "$ROOT_DIR"/files/kyverno/*.yaml 2>/dev/null | \
  xargs -I{} basename {} .yaml | sort -u >> "$ENFORCE_FILE" || true

# b) From per-policy overrides in values.yaml
awk '
  $0 ~ /^kyverno:/ { inK=1; next }
  inK && $0 ~ /^  policies:/ { inP=1; next }
  inK && inP {
    if ($0 ~ /^    [A-Za-z0-9._-]+:/) { gsub(/^ +/,"",$0); split($0,a,":"); cur=a[1]; next }
    if (tolower($0) ~ /validationfailureaction:[[:space:]]*enforce/) { print cur }
  }
' "$VALUES_FILE" | sort -u >> "$ENFORCE_FILE"

# De-duplicate
sort -u "$ENFORCE_FILE" -o "$ENFORCE_FILE"

missing_list=""
while IFS= read -r pol; do
  [[ -z "$pol" ]] && continue
  # Extract policy block from values.yaml: start at exact key line and stop at next key or dedent
  if ! awk -v target="$pol" '
      $0 ~ ("^    " target ":") { inBlock=1; next }
      inBlock {
        # End of block when a new sibling key appears
        if ($0 ~ /^    [A-Za-z0-9._-]+:/) { exit }
        # Keep nested fields (6 spaces) and 4-space comment lines
        if ($0 ~ /^      / || $0 ~ /^    #/) { print }
      }
    ' "$VALUES_FILE" | grep -qi 'rationale:'; then
    missing_list+="$pol
"
  fi
done < "$ENFORCE_FILE"

if [[ -n "$missing_list" ]]; then
  echo "Missing rationale comments for enforced policies:" >&2
  printf '%s' "$missing_list" | sed '/^$/d; s/^/  - /' >&2
  echo "Add a '# rationale: <text>' comment inside each policy block in values.yaml." >&2
  exit 1
fi

echo "All enforced policies have rationale comments." >&2
