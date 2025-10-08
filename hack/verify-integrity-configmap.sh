#!/usr/bin/env bash
# verify-integrity-configmap.sh
# Ensures that when build.exportIntegrityConfigMap=true and integritySha256 is non-empty
# a ConfigMap with the expected name and annotations is rendered.
# Usage: hack/verify-integrity-configmap.sh [--values values.yaml]
set -euo pipefail

values_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --values) values_file="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

chart_dir="$(cd "$(dirname "$0")/.." && pwd)"
vf="${values_file:-$chart_dir/values.yaml}"

export_flag=$(yq -r '.build.exportIntegrityConfigMap // false' "$vf" 2>/dev/null || echo false)
hash_val=$(yq -r '.build.integritySha256 // ""' "$vf" 2>/dev/null || echo "")
name_override=$(yq -r '.build.integrityConfigMapName // ""' "$vf" 2>/dev/null || echo "")

if [[ "$export_flag" != "true" || -z "$hash_val" ]]; then
  echo "Skip: exportIntegrityConfigMap not enabled or integritySha256 empty" >&2
  exit 0
fi

expected_name=${name_override:-policy-sets-integrity}
tmp_render="$(mktemp)"; trap 'rm -f "$tmp_render"' EXIT
helm template rulehub-policies "$chart_dir" -f "$vf" > "$tmp_render" || true
if grep -qE '^Error:' "$tmp_render"; then
  echo "Helm template errors present" >&2
  grep -E '^Error:' "$tmp_render" >&2 || true
  exit 1
fi

doc=$(awk -v name="$expected_name" 'BEGIN{RS="---"} $0 ~ "kind: ConfigMap" && $0 ~ "name: "name {print; exit}' "$tmp_render") || true
if [[ -z "$doc" ]]; then
  echo "FAIL: Integrity ConfigMap '$expected_name' not found in rendered output" >&2
  exit 1
fi
if ! grep -q "policy-sets/build.integrity.sha256: $hash_val" <<<"$doc"; then
  echo "FAIL: Integrity annotation missing or mismatched" >&2
  exit 1
fi
echo "Integrity ConfigMap present and valid ($expected_name)"
