#!/usr/bin/env bash
set -euo pipefail
# Render chart across a matrix of profile/value scenarios and report counts.
# This is a lightweight helper; in CI integrate via chart-testing matrix later.
# Scenarios: minimal (all disabled), full (default values.yaml), gatekeeper-only, kyverno-only.
# Future: add generated composite profiles via profiles.* definitions.

CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELM_BIN=${HELM_BIN:-helm}
VALUES_DEFAULT="$CHART_DIR/values.yaml"
EXAMPLES_DIR="$CHART_DIR/examples"

err() { echo "[matrix] $*" >&2; }

render_count() {
  local file="$1"
  local name="$2"
  if [[ ! -f "$file" ]]; then err "missing values file $file"; return 1; fi
  local out
  if ! out=$($HELM_BIN template "$CHART_DIR" -f "$file" 2>&1); then
    err "render failed for scenario=$name"; echo "$out" >&2; return 1; fi
  # Count docs by '---' boundaries (first doc may not start with ---); count 'kind:' occurrences instead.
  local count kindcount
  kindcount=$(printf '%s' "$out" | grep -E '^kind:' | wc -l | tr -d ' ')
  echo "scenario=$name kind_count=$kindcount"
}

main() {
  render_count "$EXAMPLES_DIR/values-minimal.yaml" minimal
  render_count "$VALUES_DEFAULT" full
  render_count "$EXAMPLES_DIR/values-gatekeeper-only.yaml" gatekeeper-only
  render_count "$EXAMPLES_DIR/values-kyverno-only.yaml" kyverno-only
}

main "$@"
