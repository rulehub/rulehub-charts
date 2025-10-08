#!/usr/bin/env bash
set -euo pipefail
# Generate per-file sha256 hashes for snapshot directory to support golden hash comparisons.
# Usage: hack/generate-snapshot-hashes.sh <snapshot_dir> [--output manifest.json]
# Produces snapshot_dir/hashes.txt (sorted) and optional JSON manifest array [{file,sha256}].

SNAP_DIR="${1:-snapshots/current}"
OUT_JSON=""
if [[ $# -ge 2 ]]; then OUT_JSON="$2"; fi

if [[ ! -d "$SNAP_DIR" ]]; then echo "Snapshot dir $SNAP_DIR not found" >&2; exit 2; fi

HASH_FILE="$SNAP_DIR/hashes.txt"
: > "$HASH_FILE"
for f in $(find "$SNAP_DIR" -maxdepth 1 -type f -name '*.yaml' ! -name 'hashes.txt' ! -name '_index.txt' | sort); do
  sha=$(sha256sum "$f" | awk '{print $1}')
  base=$(basename "$f")
  printf '%s  %s\n' "$sha" "$base" >> "$HASH_FILE"
done
sort -o "$HASH_FILE" "$HASH_FILE"
 echo "Wrote hashes: $(wc -l < "$HASH_FILE") entries -> $HASH_FILE"

if [[ -n "$OUT_JSON" ]]; then
  if command -v jq >/dev/null 2>&1; then
    jq -Rn '[inputs | capture("^(?<sha>[a-f0-9]{64})  (?<file>.+)$") ]' < "$HASH_FILE" > "$OUT_JSON.tmp" || true
    # Remove null entries
    jq '[.[] | select(.!=null)]' "$OUT_JSON.tmp" > "$OUT_JSON"
    rm -f "$OUT_JSON.tmp"
    echo "JSON manifest written: $OUT_JSON"
  else
    echo "jq not found; skipping JSON manifest" >&2
  fi
fi
