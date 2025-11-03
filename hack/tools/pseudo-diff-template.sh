#!/usr/bin/env bash
set -euo pipefail
# Generate a pseudo diff between current chart render and a previous packaged release (tgz or directory).
# Usage:
#   hack/pseudo-diff-template.sh --prev path/to/old/chart.tgz [--values values.yaml] [--output diff.txt]
# Notes:
# - We render both with 'helm template' using the provided (or default) values file.
# - We normalize output to reduce noise (remove helm headers, blank trailing spaces, timestamps if any).
# - If previous is a .tgz we extract to a temp dir.
# - Output is a unified diff (context 5) or a summary if identical.

PREV=""
VALUES_FILE="values.yaml"
OUT=""
CHART_CUR="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prev)
      PREV="$2"; shift 2;;
    --values)
      VALUES_FILE="$2"; shift 2;;
    --output)
      OUT="$2"; shift 2;;
    --chart)
      CHART_CUR="$2"; shift 2;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
done

if [[ -z "$PREV" ]]; then
  echo "--prev path to previous chart (directory or .tgz) required" >&2
  exit 2
fi

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "Values file $VALUES_FILE not found" >&2
  exit 2
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Prepare previous chart directory
if [[ -d "$PREV" ]]; then
  PREV_DIR="$PREV"
else
  if [[ ! -f "$PREV" ]]; then
    echo "Previous chart artifact $PREV not found" >&2
    exit 2
  fi
  tar -xzf "$PREV" -C "$TMP_DIR"
  # Assume single chart inside
  PREV_DIR="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n1)"
fi

CUR_OUT="$TMP_DIR/current.yaml"
PREV_OUT="$TMP_DIR/prev.yaml"

helm template rulehub "$CHART_CUR" --values "$VALUES_FILE" > "$CUR_OUT"
helm template rulehub "$PREV_DIR" --values "$VALUES_FILE" > "$PREV_OUT"

normalize() {
  sed -E 's/[[:space:]]+$//' "$1" | \
    grep -v '^# Source: ' | \
    awk 'NF>0 || last_blank==0 {print; last_blank = (NF==0)}' | \
    sed -E 's/([Cc]reation[Tt]imestamp:).*/\1 <normalized>/'
}

normalize "$CUR_OUT" > "$CUR_OUT.norm"
normalize "$PREV_OUT" > "$PREV_OUT.norm"

if diff -q "$PREV_OUT.norm" "$CUR_OUT.norm" >/dev/null; then
  echo "No differences in rendered manifests (after normalization)."
  exit 0
fi

# Produce unified diff
if command -v diff >/dev/null 2>&1; then
  DIFF_CONTENT=$(diff -u -U5 "$PREV_OUT.norm" "$CUR_OUT.norm" || true)
else
  echo "diff utility not found" >&2
  exit 3
fi

if [[ -n "$OUT" ]]; then
  echo "$DIFF_CONTENT" > "$OUT"
  echo "Pseudo diff written to $OUT" >&2
else
  echo "$DIFF_CONTENT"
fi

# Provide a short summary of change categories
added=$(grep '^+kind:' "$CUR_OUT.norm" | wc -l || true)
removed=$(grep '^-kind:' "$CUR_OUT.norm" | wc -l || true)
# This is a naive estimation; a more advanced script could classify modifications per resource identity.
echo "Summary: added kind lines: $added, removed kind lines: $removed" >&2
