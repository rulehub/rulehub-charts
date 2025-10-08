#!/usr/bin/env bash
set -euo pipefail
# Detect duplicate policy keys where both hyphen and underscore variants exist in values.yaml
# Canonical form is with hyphens. Underscore variant is considered deprecated.
# Output: tab-separated list: deprecated_key <TAB> canonical_key

VALUES_FILE="$(dirname "$0")/../values.yaml"

# Extract policy keys (gatekeeper + kyverno)
# We assume indentation pattern: two spaces, then key ending with ':' and nested 'enabled:'
# We'll just grep lines with two leading spaces and alphanum start; adjust as needed.
keys=$(awk '/^ {4}[A-Za-z0-9][A-Za-z0-9_.-]*:$/ {gsub(":","",$1); print $1}' "$VALUES_FILE")

# Build maps
declare -A by_norm
declare -A original

while IFS= read -r k; do
  norm=${k//_/ -}  # temp replace underscores with space-hyphen? mistake. We'll just replace '_' with '-'
  norm=${k//_/ -}
  # Correct replacement
  norm=${k//_/ -}
  # Actually simpler: use parameter expansion properly
  norm=${k//_/ -}
  # Real normalized: replace underscores with hyphens
  norm=${k//_/ -}
  # This got messy due to sed attempt; fallback to sed
  norm=$(echo "$k" | sed 's/_/-/g')
  by_norm[$norm]="${by_norm[$norm]:-}${k} "
  original[$k]=1
done <<< "$keys"

echo -e "# Deprecated underscore variant\n# deprecated_key\tcanonical_key" >&2

found=0
for norm in "${!by_norm[@]}"; do
  variants=( ${by_norm[$norm]} )
  # Need at least two variants and at least one with underscore and one with hyphen difference
  if [ ${#variants[@]} -ge 2 ]; then
    # pick canonical: the one without underscores, prefer with hyphens
    canonical=""
    for v in "${variants[@]}"; do
      if [[ "$v" != *"_"* ]]; then
        canonical=$v
        break
      fi
    done
    [ -z "$canonical" ] && canonical=${variants[0]}
    for v in "${variants[@]}"; do
      if [[ "$v" != "$canonical" && "$v" == *"_"* ]]; then
        echo -e "$v\t$canonical"
        found=1
      fi
    done
  fi
done | sort | tee /dev/stderr

if [ $found -eq 0 ]; then
  echo "No underscore duplicate variants found" >&2
fi
