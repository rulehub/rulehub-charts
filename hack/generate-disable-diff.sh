#!/usr/bin/env bash
set -euo pipefail

# generate-disable-diff.sh
# Produces a unified diff (patch) that would set enabled: false for the given policy keys
# in values.yaml (supports gatekeeper.policies.* and kyverno.policies.*). If a key is not
# found it is reported to stderr. The diff can be applied with 'patch -p0'.
# Usage:
#   ./hack/generate-disable-diff.sh key1 key2 ...
# Keys should be specified WITHOUT the leading framework prefix, e.g.:
#   betting-aml_sar_reporting_uk-policy betting-aml_sar_reporting_uk-constraint
# The script auto-detects whether the key belongs to gatekeeper or kyverno sections
# by searching under the respective policies nodes. If a key exists in both, both
# occurrences are toggled.

VALUES_FILE="$(dirname "$0")/../values.yaml"

if [[ $# -lt 1 ]]; then
  echo "Provide at least one policy key (basename)." >&2
  exit 1
fi
if [[ ! -f "$VALUES_FILE" ]]; then
  echo "values.yaml not found at $VALUES_FILE" >&2
  exit 2
fi

# We build a temporary modified copy then diff.
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
cp "$VALUES_FILE" "$TMP_DIR/original.values.yaml"
cp "$VALUES_FILE" "$TMP_DIR/modified.values.yaml"

# Function to disable a policy key inside modified file.
disable_key() {
  local key="$1"; shift || true
  # Use awk to locate the line with '  <key>:' under either framework policies section and then change the subsequent 'enabled:' value.
  # We'll do a two-pass: first find line numbers, then edit via sed.
  local matches
  # Grep pattern ensures exact key followed by colon at indentation >=4 spaces
  matches=$(grep -nE "^[[:space:]]{4}${key}:$" "$TMP_DIR/modified.values.yaml" || true)
  if [[ -z "$matches" ]]; then
    echo "Key not found: $key" >&2
    return 1
  fi
  while IFS= read -r m; do
    [[ -z "$m" ]] && continue
    local lineno=${m%%:*}
    # Search following few lines (up to 5) for 'enabled:' and replace true->false (or add if missing)
    local window_end=$((lineno+5))
    if sed -n "${lineno},${window_end}p" "$TMP_DIR/modified.values.yaml" | grep -qE "^[[:space:]]{6}enabled:"; then
      # Replace only the first occurrence in that window
      # Use perl for precise range editing
      perl -0777 -i -pe "s/(^ {6}enabled: )[Tt]rue/\${1}false/m if $.==0;" "$TMP_DIR/modified.values.yaml" 2>/dev/null || {
        # Fallback sed in-place within range
        awk -v start=$lineno -v end=$window_end 'NR>=start && NR<=end { if($1=="enabled:" && $2!="false") $0="      enabled: false" } {print}' "$TMP_DIR/modified.values.yaml" > "$TMP_DIR/tmp.swap" && mv "$TMP_DIR/tmp.swap" "$TMP_DIR/modified.values.yaml"
      }
      # Simpler deterministic replacement in whole file line anchored
      sed -i "${lineno},${window_end}s/^\(      enabled: \).*/\1false/" "$TMP_DIR/modified.values.yaml"
    else
      # Add enabled: false two spaces deeper than key indent
      awk -v keyline=$lineno 'NR==keyline{print;print"      enabled: false";next} {print}' "$TMP_DIR/modified.values.yaml" > "$TMP_DIR/tmp.swap" && mv "$TMP_DIR/tmp.swap" "$TMP_DIR/modified.values.yaml"
    fi
  done <<< "$matches"
}

status=0
for k in "$@"; do
  if ! disable_key "$k"; then
    status=1
  fi
done

# Produce diff (unified) relative path
if command -v gnu-diff >/dev/null 2>&1; then
  DIFF=gnu-diff
else
  DIFF=diff
fi

$DIFF -u "$TMP_DIR/original.values.yaml" "$TMP_DIR/modified.values.yaml" | sed '1,2s#'$TMP_DIR'/##g' || true

exit $status
