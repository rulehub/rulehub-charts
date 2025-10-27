#!/usr/bin/env bash
# verify-chart-version-label.sh
# Ensures every rendered manifest (helm template) contains metadata.labels["chart/version"].
# Fails if helm template output contains lines beginning with 'Error:'.
# Usage: hack/verify-chart-version-label.sh [--quiet] [VALUES_FILE]
#   --quiet : suppress success output (only errors)
set -euo pipefail

quiet=false
args=()
for a in "$@"; do
  case "$a" in
    --quiet) quiet=true ;;
    *) args+=("$a") ;;
  esac
done
# Reset positional args safely under `set -u` even if args is empty (macOS Bash compatibility)
if [ ${#args[@]} -gt 0 ]; then
  set -- "${args[@]}"
else
  set --
fi

CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VALUES_FILE="${1:-$CHART_DIR/values.yaml}"
TMP_RENDER="$(mktemp)"
trap 'rm -f "$TMP_RENDER"' EXIT

helm template rulehub-policies "$CHART_DIR" -f "$VALUES_FILE" > "$TMP_RENDER" || true

if grep -qE '^Error:' "$TMP_RENDER"; then
  echo "Helm template produced error lines:" >&2
  grep -E '^Error:' "$TMP_RENDER" >&2 || true
  exit 1
fi

missing=()
current=""
while IFS= read -r line || [ -n "$line" ]; do
  if [[ "$line" =~ ^--- ]]; then
    if [[ -n "$current" ]]; then
      # Skip non-resource blocks (no kind present)
      if ! grep -q '^kind:' <<<"$current"; then
        : # ignore preamble or non-YAML blocks
      elif ! grep -q "chart/version:" <<<"$current"; then
        kind=$(grep -m1 '^kind:' <<<"$current" | awk '{print $2}') || true
        name=$(grep -m1 '^  name:' <<<"$current" | awk '{print $2}') || true
        [[ -z "$name" ]] && name=$(grep -m1 '^metadata:' -A3 <<<"$current" | grep '^  name:' | awk '{print $2}') || true
        missing+=("${kind:-Unknown}/${name:-Unknown}")
      fi
    fi
    current=""
    continue
  fi
  current+="$line"$'\n'
done < "$TMP_RENDER"

if [[ -n "$current" ]]; then
  if ! grep -q '^kind:' <<<"$current"; then
    :
  elif ! grep -q "chart/version:" <<<"$current"; then
    kind=$(grep -m1 '^kind:' <<<"$current" | awk '{print $2}') || true
    name=$(grep -m1 '^  name:' <<<"$current" | awk '{print $2}') || true
    [[ -z "$name" ]] && name=$(grep -m1 '^metadata:' -A3 <<<"$current" | grep '^  name:' | awk '{print $2}') || true
    missing+=("${kind:-Unknown}/${name:-Unknown}")
  fi
fi

if ((${#missing[@]})); then
  echo "Missing chart/version label in resources:" >&2
  for m in "${missing[@]}"; do echo "  - $m" >&2; done
  exit 1
fi

if ! $quiet; then
  echo "All rendered resources have chart/version label." >&2
fi
