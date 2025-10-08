#!/usr/bin/env bash
set -euo pipefail
# fuzz-policies.sh
# Randomizes enabled flags for Gatekeeper and Kyverno policies and ensures helm template succeeds.
# Usage: hack/fuzz-policies.sh [--runs 20] [--values values.yaml] [--seed 123]
# Environment: FUZZ_GATEKEEPER=1 FUZZ_KYVERNO=1 (both default on if sections enabled)
# Exits non-zero on first failure. Prints summary.

RUNS=20
VALUES_FILE="values.yaml"
SEED=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs) RUNS="$2"; shift 2 ;;
    --values) VALUES_FILE="$2"; shift 2 ;;
    --seed) SEED="$2"; shift 2 ;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# //' ; exit 0 ;;
    *) echo "Unknown arg $1" >&2; exit 2 ;;
  esac
done

if ! command -v yq >/dev/null 2>&1; then echo "yq required" >&2; exit 2; fi
if ! command -v helm >/dev/null 2>&1; then echo "helm required" >&2; exit 2; fi

CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)"

gatekeeper_keys=$(yq '.gatekeeper.policies | keys | .[]' "$VALUES_FILE" 2>/dev/null || true)
kyverno_keys=$(yq '.kyverno.policies | keys | .[]' "$VALUES_FILE" 2>/dev/null || true)

if [[ -n "$SEED" ]]; then RANDOM="$SEED"; fi

passes=0
for i in $(seq 1 "$RUNS"); do
  overlay=$(mktemp)
  {
    echo "gatekeeper:"; echo "  enabled: true"; echo "  policies:";
    for k in $gatekeeper_keys; do
      r=$((RANDOM % 2)); bool="false"; [[ $r -eq 1 ]] && bool="true";
      printf '    %s:\n      enabled: %s\n' "$k" "$bool"
    done
    echo "kyverno:"; echo "  enabled: true"; echo "  policies:";
    for k in $kyverno_keys; do
      r=$((RANDOM % 2)); bool="false"; [[ $r -eq 1 ]] && bool="true";
      printf '    %s:\n      enabled: %s\n' "$k" "$bool"
    done
  } > "$overlay"
  if ! helm template rulehub-policies "$CHART_DIR" -f "$VALUES_FILE" -f "$overlay" >/dev/null 2>"$overlay.err"; then
    echo "FUZZ FAIL run=$i (helm template error)" >&2
    sed -n '1,50p' "$overlay.err" >&2
    echo "Overlay file at: $overlay" >&2
    exit 1
  fi
  if grep -q '^Error:' "$overlay.err"; then
    echo "FUZZ FAIL run=$i (Error: lines in output)" >&2
    sed -n '1,50p' "$overlay.err" >&2
    echo "Overlay file at: $overlay" >&2
    exit 1
  fi
  rm -f "$overlay" "$overlay.err" || true
  passes=$((passes+1))
done

echo "FUZZ OK runs=$passes"
