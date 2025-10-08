#!/usr/bin/env bash
set -euo pipefail

# verify-id-annotation.sh
#
# Purpose:
#   Scan all policy YAML files under files/{kyverno,gatekeeper,gatekeeper-templates}
#   and verify each contains at least one annotation line starting with 'rulehub.id:'.
#
# Output:
#   - Lists files missing the annotation (one per line) and exits with code 1 if any are missing.
#   - Prints success message and exits 0 if all files contain the annotation.
#
# Notes:
#   - Multi-document YAML: only checks presence anywhere in the file (first document expected to hold annotations).
#   - Skips non-regular files defensively.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"

total=0
missing_count=0
missing_list=""

while IFS= read -r f; do
  [ -n "$f" ] || continue
  total=$((total+1))
  if ! grep -qE '^[[:space:]]*rulehub.id:' "$f"; then
    missing_count=$((missing_count+1))
    missing_list+=$'  - '"$f"$'\n'
  fi
done < <(find "$REPO_ROOT/files" -maxdepth 2 -type f -name '*.yaml' | sort)

echo "[verify-id-annotation] Files scanned: $total" >&2

if [ "$missing_count" -gt 0 ]; then
  echo 'Missing rulehub.id annotation in:'
  printf '%s' "$missing_list"
  echo
  echo "Total without annotation: $missing_count" >&2
  exit 1
else
  echo 'All YAML policy files contain rulehub.id annotation.'
fi
