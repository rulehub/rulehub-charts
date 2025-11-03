#!/usr/bin/env sh
# verify-underscore-gate.sh
# Purpose: CI gate preventing introduction of NEW policy keys containing '_' (underscore)
#          unless a dash-normalized companion key already exists in the same commit.
#
# Rationale: Canonical policy keys use kebab-case (dashes). Underscore variants are
# deprecated aliases kept temporarily for backwards compatibility. Introducing a new
# underscore form without simultaneously adding the dash form would create technical
# debt and migration churn.
#
# Detection strategy (default):
#  * Compute git diff vs BASE ref (default: HEAD~) for values.yaml additions.
#  * Extract newly added policy keys (lines like '    some_key:').
#  * For each newly added key containing '_' derive dash form by replacing '_' -> '-'.
#  * If the dash form is NOT present anywhere in the current values.yaml (as a key
#    under any <framework>.policies map) => violation.
#
# Optional yq enhancement: If 'yq' is available, existence checks prefer semantic
# lookup (e.g., .kyverno.policies["dash-key"]) to avoid false positives from comments.
# Falls back to grep when yq absent.
#
# Exit codes:
#  0 - OK (no violations)
#  1 - Violations detected
#  2 - Usage / internal error
#
# Usage:
#   hack/verify-underscore-gate.sh [--base <git-ref>] [--file values.yaml]
# Examples:
#   hack/verify-underscore-gate.sh            # diff vs HEAD~
#   hack/verify-underscore-gate.sh --base origin/main
#
# Output: Human-readable list of violating keys. Set GATE_QUIET=1 to suppress OK message.

set -eu

BASE="HEAD~"
VALUES_FILE="values.yaml"
QUIET="${GATE_QUIET:-0}"

while [ $# -gt 0 ]; do
  case "$1" in
    --base) shift; BASE="${1:-}"; [ -z "$BASE" ] && { echo "Missing value after --base" >&2; exit 2; } ;;
    --file) shift; VALUES_FILE="${1:-}"; [ -z "$VALUES_FILE" ] && { echo "Missing value after --file" >&2; exit 2; } ;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# //'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
  shift || true
done

if [ ! -f "$VALUES_FILE" ]; then
  echo "File not found: $VALUES_FILE" >&2
  exit 2
fi

# Ensure we have a diff base commit; if first commit, skip gracefully.
if ! git rev-parse --verify "$BASE" >/dev/null 2>&1; then
  echo "Base ref not found: $BASE (skipping)" >&2
  exit 0
fi

# Extract added lines for values.yaml only.
DIFF=$(git diff -U0 "$BASE" -- "$VALUES_FILE" || true)

# If file newly added, treat all keys as added.
if printf '%s' "$DIFF" | grep -q '^new file mode'; then
  DIFF=$(sed 's/^/+/;' "$VALUES_FILE")
fi

# Collect newly added keys containing underscores.
ADDED_UNDERSCORE_KEYS=$(printf '%s' "$DIFF" \
  | grep '^+' \
  | grep -v '^+++ ' \
  | grep -E '^\+ {4}[A-Za-z0-9._-]+:' \
  | sed -E 's/^\+ {4}([A-Za-z0-9._-]+):.*/\1/' \
  | grep '_' || true)

if [ -z "$ADDED_UNDERSCORE_KEYS" ]; then
  [ "$QUIET" = 1 ] || echo "Underscore gate: no new underscore keys added (OK)"
  exit 0
fi

violations=""

# Helper: check if dash key exists (yq semantic if available, else grep)
dash_exists() {
  dk="$1"
  if command -v yq >/dev/null 2>&1; then
    # Check under both kyverno.policies and gatekeeper.policies (cheap)
    if yq -e ".kyverno.policies | has(\"$dk\")" "$VALUES_FILE" >/dev/null 2>&1; then return 0; fi
    if yq -e ".gatekeeper.policies | has(\"$dk\")" "$VALUES_FILE" >/dev/null 2>&1; then return 0; fi
    return 1
  else
    # Fallback grep (exact key at 4-space indent)
    grep -Eq "^ {4}$dk:" "$VALUES_FILE" 2>/dev/null
  fi
}

printf '%s\n' "$ADDED_UNDERSCORE_KEYS" | while IFS= read -r key; do
  [ -n "$key" ] || continue
  dash_key=$(printf '%s' "$key" | tr '_' '-')
  # If dash form equals original (no underscores) skip.
  [ "$dash_key" = "$key" ] && continue
  if ! dash_exists "$dash_key"; then
    violations="$violations\n  - $key (expected dash pair: $dash_key)"
  fi
done

if [ -n "$violations" ]; then
  echo "Underscore gate violations (missing dash counterparts):" >&2
  printf '%s\n' "$violations" >&2
  exit 1
fi

[ "$QUIET" = 1 ] || echo "Underscore gate: all new underscore keys have dash pairs (OK)"
exit 0
