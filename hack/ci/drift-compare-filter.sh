#!/usr/bin/env bash
set -euo pipefail

# drift-compare-filter.sh
# Run charts drift comparison from within the cloned RuleHub repo directory
# and filter results to curated domains, ignoring placeholders and k8s id-shape noise.
#
# Usage:
#   ./hack/ci/drift-compare-filter.sh \
#     --charts-dir ../files \
#     --allowed '["betting.","edtech.","medtech.","igaming."]' \
#     [--fail-on-drift]
#
# Inputs:
#   --charts-dir  Path to chart files directory (relative to current cwd)
#   --allowed     JSON array of string prefixes allowed in drift report
#   --fail-on-drift  Exit non-zero if filtered drift exists (default: off)

CHARTS_DIR="../files"
ALLOWED='["betting.","edtech.","medtech.","igaming."]'
FAIL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --charts-dir)
      CHARTS_DIR="$2"; shift 2;;
    --allowed)
      ALLOWED="$2"; shift 2;;
    --fail-on-drift)
      FAIL=1; shift;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

python tools/compare_charts_policies.py --charts-dir "$CHARTS_DIR" --json > charts-drift.json

jq -r --argjson allowed "$ALLOWED" '
  def allowed: any($allowed[]; . as $p | startswith($p));
  {
    filtered_missing:   (.missing_in_charts // []) | map(select(allowed)),
    filtered_extra:     (.extra_in_charts    // [])
                          | map(select(allowed))
                          | map(select(. != "betting.constraint.placeholder" and . != "betting.policy.placeholder"))
  } | . + { missing_count: (.filtered_missing|length), extra_count: (.filtered_extra|length) }' charts-drift.json > charts-drift.filtered.json

echo "missing=$(jq -r '.missing_count' charts-drift.filtered.json) extra=$(jq -r '.extra_count' charts-drift.filtered.json)"

if [[ $FAIL -eq 1 ]]; then
  M=$(jq -r '.missing_count' charts-drift.filtered.json)
  E=$(jq -r '.extra_count' charts-drift.filtered.json)
  if [[ "$M" != "0" || "$E" != "0" ]]; then
    exit 2
  fi
fi
